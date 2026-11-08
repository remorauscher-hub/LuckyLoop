import java.io.File;
import java.io.RandomAccessFile;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Single Hap1 (DXT1) loop on disk. Async ordered encode; prefetch decode for play.
 * Fixed frame size → O(1) seek (Resolume Hap thinking, no MOV/Snappy).
 */
public final class HapLoopStore {
  static final int MAGIC = 0x4C4C4850; // LLHP
  static final int VERSION = 1;
  static final int HEADER = 32;
  // Small window — each slot is a full RGB frame. Multi-layer stacks used to
  // run one reader per Hap file and crush the live view; keep this lean.
  static final int PREFETCH = 4;
  static final int QUEUE = 24;
  static final int ENCODERS = 3;

  final Object lock = new Object();
  int w;
  int h;
  int fps;
  int dxtSize;
  int frameCount;
  File file;
  boolean ready;

  private RandomAccessFile raf;
  private Thread[] encoders;
  private Thread diskWriter;
  private Thread reader;
  private final AtomicBoolean writing = new AtomicBoolean(false);
  private final AtomicBoolean reading = new AtomicBoolean(false);
  private final AtomicBoolean writerFailed = new AtomicBoolean(false);
  private volatile String fail = "";
  private final AtomicInteger submitSeq = new AtomicInteger(0);
  private final AtomicInteger writeSeq = new AtomicInteger(0);
  private final AtomicInteger written = new AtomicInteger(0);
  private volatile int wantHead = 0;

  private ArrayBlockingQueue<RawJob> freeRaw;
  private ArrayBlockingQueue<RawJob> encodeQ;
  private ArrayBlockingQueue<DxtJob> freeDxt;
  private ArrayBlockingQueue<DxtJob> writeQ;
  private final Object orderLock = new Object();
  private DxtJob[] ordered;
  private int orderNext;

  private byte[] readDxt;
  private final Object cacheLock = new Object();
  private int[][] cacheRgb;
  private int[] cacheIdx;
  private int[] cacheStamp;
  private int stamp;

  private static final class RawJob {
    int seq;
    int[] rgb;
  }

  private static final class DxtJob {
    int seq;
    byte[] dxt;
  }

  public String failMessage() {
    return fail;
  }

  public int recordedFrames() {
    return written.get();
  }

  public boolean hasLoop() {
    return ready && frameCount > 0 && file != null;
  }

  public void prepare(int width, int height, int frameRate) {
    close();
    w = width;
    h = height;
    fps = Math.max(1, frameRate);
    dxtSize = HapCodec.dxt1Size(w, h);
    frameCount = 0;
    ready = false;
    fail = "";
    writerFailed.set(false);
    written.set(0);
    submitSeq.set(0);
    writeSeq.set(0);
  }

  public boolean beginRecord(File dest) {
    prepare(w > 0 ? w : 1920, h > 0 ? h : 1080, fps > 0 ? fps : 25);
    try {
      if (dest.getParentFile() != null) dest.getParentFile().mkdirs();
      if (dest.exists() && !dest.delete()) throw new IllegalStateException("Can't replace " + dest.getName());
      file = dest;
      raf = new RandomAccessFile(dest, "rw");
      Header hdr = new Header();
      hdr.put(MAGIC, VERSION, w, h, fps, 0, dxtSize);
      raf.write(hdr.bytes);
      raf.setLength(HEADER);

      freeRaw = new ArrayBlockingQueue<RawJob>(QUEUE);
      encodeQ = new ArrayBlockingQueue<RawJob>(QUEUE);
      freeDxt = new ArrayBlockingQueue<DxtJob>(QUEUE);
      writeQ = new ArrayBlockingQueue<DxtJob>(QUEUE);
      ordered = new DxtJob[QUEUE * 2];
      orderNext = 0;
      for (int i = 0; i < QUEUE; i++) {
        RawJob rj = new RawJob();
        rj.rgb = new int[w * h];
        freeRaw.add(rj);
        DxtJob dj = new DxtJob();
        dj.dxt = new byte[dxtSize];
        freeDxt.add(dj);
      }

      writing.set(true);
      writerFailed.set(false);
      written.set(0);
      submitSeq.set(0);
      writeSeq.set(0);

      encoders = new Thread[ENCODERS];
      for (int i = 0; i < ENCODERS; i++) {
        encoders[i] = new Thread(new Runnable() {
          public void run() {
            encodeLoop();
          }
        }, "hap-encode-" + i);
        encoders[i].setDaemon(true);
        encoders[i].setPriority(Thread.NORM_PRIORITY + 1);
        encoders[i].start();
      }
      diskWriter = new Thread(new Runnable() {
        public void run() {
          diskLoop();
        }
      }, "hap-disk");
      diskWriter.setDaemon(true);
      diskWriter.start();
      return true;
    } catch (Exception e) {
      fail = e.getMessage();
      close();
      return false;
    }
  }

  public boolean offerFrame(int[] argb) {
    if (!writing.get() || argb == null || argb.length < w * h) return false;
    RawJob job = freeRaw.poll();
    if (job == null) return false;
    System.arraycopy(argb, 0, job.rgb, 0, w * h);
    job.seq = submitSeq.getAndIncrement();
    if (!encodeQ.offer(job)) {
      freeRaw.offer(job);
      return false;
    }
    return true;
  }

  public boolean finishRecord(int maxFrames) {
    if (!writing.get() && written.get() == 0) return false;
    writing.set(false);
    joinWorkers(20000);
    int n = Math.min(written.get(), maxFrames);
    if (writerFailed.get() || n < 2) {
      closeFileOnly();
      ready = false;
      frameCount = 0;
      return false;
    }
    try {
      frameCount = n;
      raf.seek(0);
      Header hdr = new Header();
      hdr.put(MAGIC, VERSION, w, h, fps, frameCount, dxtSize);
      raf.write(hdr.bytes);
      raf.getFD().sync();
      ready = true;
      startReader();
      return true;
    } catch (Exception e) {
      fail = e.getMessage();
      close();
      return false;
    }
  }

  /** Duplicate the last DXT frame so playback length matches wall-clock record time. */
  public boolean padToFrames(int target) {
    if (!ready || raf == null || frameCount < 1 || target <= frameCount) {
      return ready && frameCount >= target;
    }
    try {
      byte[] last = new byte[dxtSize];
      synchronized (lock) {
        raf.seek(HEADER + (long) (frameCount - 1) * dxtSize);
        raf.readFully(last);
        for (int i = frameCount; i < target; i++) {
          raf.seek(HEADER + (long) i * dxtSize);
          raf.write(last);
        }
        frameCount = target;
        raf.seek(0);
        Header hdr = new Header();
        hdr.put(MAGIC, VERSION, w, h, fps, frameCount, dxtSize);
        raf.write(hdr.bytes);
        raf.getFD().sync();
      }
      return true;
    } catch (Exception e) {
      fail = e.getMessage();
      return false;
    }
  }

  /** Keep only the first target frames (header trim; used to lock wall-clock length). */
  public boolean trimToFrames(int target) {
    if (!ready || raf == null || frameCount < 1 || target >= frameCount || target < 2) {
      return ready && frameCount >= 2;
    }
    try {
      synchronized (lock) {
        frameCount = target;
        raf.seek(0);
        Header hdr = new Header();
        hdr.put(MAGIC, VERSION, w, h, fps, frameCount, dxtSize);
        raf.write(hdr.bytes);
        raf.getFD().sync();
      }
      return true;
    } catch (Exception e) {
      fail = e.getMessage();
      return false;
    }
  }

  public void cancelRecord() {
    writing.set(false);
    joinWorkers(8000);
    close();
  }

  /** Open an existing Hap1 loop file for playback. */
  public boolean openExisting(File src) {
    close();
    if (src == null || !src.exists()) {
      fail = "Missing loop file";
      return false;
    }
    try {
      file = src;
      raf = new RandomAccessFile(src, "r");
      byte[] hb = new byte[HEADER];
      raf.readFully(hb);
      java.nio.ByteBuffer b = java.nio.ByteBuffer.wrap(hb).order(java.nio.ByteOrder.LITTLE_ENDIAN);
      int magic = b.getInt();
      int version = b.getInt();
      w = b.getInt();
      h = b.getInt();
      fps = b.getInt();
      frameCount = b.getInt();
      dxtSize = b.getInt();
      if (magic != MAGIC || version < 1) throw new IllegalArgumentException("Not a Hap loop");
      if (dxtSize != HapCodec.dxt1Size(w, h)) throw new IllegalArgumentException("Bad DXT size");
      if (frameCount < 1) throw new IllegalArgumentException("Empty loop");
      ready = true;
      startReader();
      return true;
    } catch (Exception e) {
      fail = e.getMessage();
      close();
      return false;
    }
  }

  public void setPlayHead(int head) {
    if (frameCount <= 0) return;
    int h0 = head % frameCount;
    if (h0 < 0) h0 += frameCount;
    wantHead = h0;
  }

  public boolean copyFrame(int head, int[] dest) {
    if (!ready || dest == null || dest.length < w * h || frameCount <= 0) return false;
    int idx = head % frameCount;
    if (idx < 0) idx += frameCount;
    wantHead = idx;
    synchronized (cacheLock) {
      for (int i = 0; i < cacheIdx.length; i++) {
        if (cacheIdx[i] == idx && cacheRgb[i] != null) {
          System.arraycopy(cacheRgb[i], 0, dest, 0, w * h);
          return true;
        }
      }
    }
    return decodeInto(idx, dest);
  }

  public void close() {
    writing.set(false);
    reading.set(false);
    joinWorkers(3000);
    try {
      if (reader != null) reader.join(2000);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
    }
    reader = null;
    closeFileOnly();
    ready = false;
    frameCount = 0;
    freeRaw = null;
    encodeQ = null;
    freeDxt = null;
    writeQ = null;
    ordered = null;
    cacheRgb = null;
  }

  private void joinWorkers(int ms) {
    try {
      if (encoders != null) {
        for (int i = 0; i < encoders.length; i++) {
          if (encoders[i] != null) encoders[i].join(ms);
        }
      }
      if (diskWriter != null) diskWriter.join(ms);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
    }
    encoders = null;
    diskWriter = null;
  }

  private void closeFileOnly() {
    try {
      if (raf != null) raf.close();
    } catch (Exception e) {
    }
    raf = null;
  }

  private void encodeLoop() {
    try {
      while (true) {
        RawJob raw = encodeQ.poll(40, TimeUnit.MILLISECONDS);
        if (raw == null) {
          if (!writing.get() && encodeQ.isEmpty()) break;
          continue;
        }
        DxtJob out = freeDxt.poll(200, TimeUnit.MILLISECONDS);
        if (out == null) {
          freeRaw.offer(raw);
          continue;
        }
        HapCodec.encodeDxt1(raw.rgb, w, h, out.dxt);
        out.seq = raw.seq;
        freeRaw.offer(raw);
        if (!writeQ.offer(out, 500, TimeUnit.MILLISECONDS)) {
          freeDxt.offer(out);
          writerFailed.set(true);
          fail = "Disk queue full";
          writing.set(false);
          break;
        }
      }
    } catch (Exception e) {
      fail = e.getMessage();
      writerFailed.set(true);
      writing.set(false);
    }
  }

  private void diskLoop() {
    try {
      while (true) {
        DxtJob job = writeQ.poll(40, TimeUnit.MILLISECONDS);
        if (job != null) {
          synchronized (orderLock) {
            int slot = job.seq - orderNext;
            if (slot >= 0 && slot < ordered.length) ordered[slot] = job;
            else {
              freeDxt.offer(job);
              writerFailed.set(true);
              fail = "Encode reorder overflow";
              writing.set(false);
              break;
            }
            while (ordered[0] != null) {
              DxtJob next = ordered[0];
              System.arraycopy(ordered, 1, ordered, 0, ordered.length - 1);
              ordered[ordered.length - 1] = null;
              long off = HEADER + (long) writeSeq.get() * dxtSize;
              synchronized (lock) {
                raf.seek(off);
                raf.write(next.dxt);
              }
              writeSeq.incrementAndGet();
              written.incrementAndGet();
              orderNext++;
              freeDxt.offer(next);
            }
          }
        } else if (!writing.get() && encodeQ.isEmpty() && writeQ.isEmpty()) {
          synchronized (orderLock) {
            if (ordered[0] == null) break;
          }
        }
      }
    } catch (Exception e) {
      fail = e.getMessage();
      writerFailed.set(true);
      writing.set(false);
    }
  }

  private void startReader() {
    reading.set(false);
    try {
      if (reader != null) reader.join(1000);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
    }
    readDxt = new byte[dxtSize];
    cacheRgb = new int[PREFETCH][];
    cacheIdx = new int[PREFETCH];
    cacheStamp = new int[PREFETCH];
    for (int i = 0; i < PREFETCH; i++) {
      cacheRgb[i] = new int[w * h];
      cacheIdx[i] = -1;
      cacheStamp[i] = 0;
    }
    stamp = 1;
    reading.set(true);
    reader = new Thread(new Runnable() {
      public void run() {
        readLoop();
      }
    }, "hap-loop-read");
    reader.setDaemon(true);
    reader.start();
  }

  private void readLoop() {
    while (reading.get() && ready) {
      int head = wantHead;
      boolean did = false;
      // Prefetch only a couple frames ahead of the playhead — avoid burning
      // CPU decoding a long window the live composite never asks for.
      int ahead = Math.min(PREFETCH, 3);
      for (int a = 0; a < ahead; a++) {
        int idx = (head + a) % frameCount;
        if (cached(idx)) continue;
        int slot = oldestSlot();
        if (decodeInto(idx, cacheRgb[slot])) {
          synchronized (cacheLock) {
            cacheIdx[slot] = idx;
            cacheStamp[slot] = ++stamp;
          }
          did = true;
          break; // one decode per wake — stay friendly to the draw thread
        }
      }
      if (!did) {
        try {
          Thread.sleep(4);
        } catch (InterruptedException e) {
          Thread.currentThread().interrupt();
          break;
        }
      }
    }
  }

  private boolean cached(int idx) {
    synchronized (cacheLock) {
      for (int i = 0; i < cacheIdx.length; i++) if (cacheIdx[i] == idx) return true;
    }
    return false;
  }

  private int oldestSlot() {
    synchronized (cacheLock) {
      int best = 0;
      int bestStamp = Integer.MAX_VALUE;
      for (int i = 0; i < cacheStamp.length; i++) {
        if (cacheIdx[i] < 0) return i;
        if (cacheStamp[i] < bestStamp) {
          bestStamp = cacheStamp[i];
          best = i;
        }
      }
      return best;
    }
  }

  private boolean decodeInto(int idx, int[] dest) {
    if (raf == null || dest == null) return false;
    try {
      long off = HEADER + (long) idx * dxtSize;
      synchronized (lock) {
        raf.seek(off);
        raf.readFully(readDxt);
      }
      HapCodec.decodeDxt1(readDxt, w, h, dest);
      return true;
    } catch (Exception e) {
      fail = e.getMessage();
      return false;
    }
  }

  private static final class Header {
    final byte[] bytes = new byte[HEADER];

    void put(int magic, int version, int w, int h, int fps, int frames, int dxt) {
      java.nio.ByteBuffer b = java.nio.ByteBuffer.wrap(bytes).order(java.nio.ByteOrder.LITTLE_ENDIAN);
      b.putInt(magic);
      b.putInt(version);
      b.putInt(w);
      b.putInt(h);
      b.putInt(fps);
      b.putInt(frames);
      b.putInt(dxt);
      b.putInt(0);
    }
  }
}

import java.io.File;

String projectDir = "";
String projectName = "";
boolean projectOpen = false;
int takeCount = 0;
int currentTake = 0;

static final int MAX_RECENT_PROJECTS = 8;
ArrayList<String> recentProjects = new ArrayList<String>();
boolean pendingNewProject = false;
boolean pendingOpenProject = false;
boolean pendingSaveAs = false;

String appPrefsPath() {
  return dataPath("app.json");
}

String defaultProjectsRoot() {
  return System.getProperty("user.home") + "/Documents/LuckyLoop Projects";
}

boolean isProjectFolder(File dir) {
  if (dir == null || !dir.isDirectory()) return false;
  if (new File(dir, "project.json").exists()) return true;
  if (new File(dir, "settings.json").exists() && new File(dir, "takes").isDirectory()) return true;
  return false;
}

void ensureProjectDirs() {
  if (!projectOpen || projectDir == null || projectDir.length() == 0) return;
  new File(projectDir).mkdirs();
  new File(projectDir, "takes").mkdirs();
  new File(projectDir, "bin").mkdirs();
  new File(projectDir, "history").mkdirs();
  new File(projectDir, "export").mkdirs();
}

boolean requireProject() {
  if (projectOpen) return true;
  note("Choose a project folder first");
  requestNewProject();
  return false;
}

File takeFolder(int take) {
  ensureProjectDirs();
  File dir = new File(projectDir, "takes/" + String.format("%03d", take));
  dir.mkdirs();
  return dir;
}

String projectSettingsPath() {
  return new File(projectDir, "settings.json").getAbsolutePath();
}

String projectMidiPath() {
  return new File(projectDir, "midi.xml").getAbsolutePath();
}

String projectMetaPath() {
  return new File(projectDir, "project.json").getAbsolutePath();
}

void loadAppPrefs() {
  recentProjects.clear();
  File f = new File(appPrefsPath());
  if (!f.exists()) return;
  try {
    JSONObject o = loadJSONObject(f.getAbsolutePath());
    JSONArray arr = o.getJSONArray("recent");
    if (arr != null) {
      for (int i = 0; i < arr.size(); i++) {
        String p = arr.getString(i);
        if (p != null && p.length() > 0 && new File(p).isDirectory()) recentProjects.add(p);
      }
    }
  } catch (Exception e) {
    println("App prefs unreadable.");
  }
}

void saveAppPrefs() {
  try {
    new File(dataPath("")).mkdirs();
    JSONObject o = new JSONObject();
    o.setString("lastProject", projectOpen ? projectDir : "");
    JSONArray arr = new JSONArray();
    for (int i = 0; i < recentProjects.size(); i++) arr.setString(i, recentProjects.get(i));
    o.setJSONArray("recent", arr);
    saveJSONObject(o, appPrefsPath());
  } catch (Exception e) {
    println("App prefs save failed: " + e.getMessage());
  }
  refreshMacRecentMenu();
}

void rememberProject(String path) {
  if (path == null || path.length() == 0) return;
  for (int i = recentProjects.size() - 1; i >= 0; i--) {
    if (path.equals(recentProjects.get(i))) recentProjects.remove(i);
  }
  recentProjects.add(0, path);
  while (recentProjects.size() > MAX_RECENT_PROJECTS) {
    recentProjects.remove(recentProjects.size() - 1);
  }
  saveAppPrefs();
}

void clearRecentProjects() {
  recentProjects.clear();
  saveAppPrefs();
  note("Recent projects cleared");
}

void refreshMacRecentMenu() {
  if (!MacMenu.loaded) return;
  int n = min(MAX_RECENT_PROJECTS, recentProjects.size());
  String[] titles = new String[n];
  String[] paths = new String[n];
  for (int i = 0; i < n; i++) {
    paths[i] = recentProjects.get(i);
    titles[i] = projectTitleForPath(paths[i]);
  }
  try {
    MacMenu.setRecents(titles, paths);
    MacMenu.install();
  } catch (Throwable t) {
    println("Recent menu update failed: " + t.getMessage());
  }
}

String projectTitleForPath(String path) {
  File dir = new File(path);
  File meta = new File(dir, "project.json");
  if (meta.exists()) {
    try {
      JSONObject o = loadJSONObject(meta.getAbsolutePath());
      String name = o.getString("name", "");
      if (name.length() > 0) return name;
    } catch (Exception e) {
    }
  }
  return dir.getName();
}

void writeProjectMeta() {
  if (!projectOpen) return;
  try {
    JSONObject o = new JSONObject();
    o.setInt("version", 1);
    o.setString("name", projectName.length() > 0 ? projectName : new File(projectDir).getName());
    o.setString("app", "LuckyLoop");
    saveJSONObject(o, projectMetaPath());
  } catch (Exception e) {
    println("project.json failed: " + e.getMessage());
  }
}

void closeProjectSession() {
  flushNotesIfDirty();
  clearLoop();
  stopResetBuffers();
  clearHist(undoHist);
  clearHist(redoHist);
  takeCount = 0;
  currentTake = 0;
  resetTextSession();
}

void updateProjectTitle() {
  surface.setTitle(projectOpen ? ("LuckyLoop — " + projectName) : "LuckyLoop");
}

void activateProject(File dir, boolean loadSettingsFromProject) {
  projectDir = dir.getAbsolutePath();
  projectName = projectTitleForPath(projectDir);
  projectOpen = true;
  ensureProjectDirs();
  writeProjectMeta();
  rememberProject(projectDir);
  if (loadSettingsFromProject) {
    File settings = new File(projectSettingsPath());
    if (settings.exists()) loadProjectSettingsFile(settings);
    else loadMidiMapFile();
  }
  loadProjectNotes();
  updateProjectTitle();
  markDirty();
  flushSettings(true);
  note("Project  " + projectName);
}

void createProjectAt(File dir) {
  if (dir == null) return;
  dir.mkdirs();
  closeProjectSession();
  projectDir = dir.getAbsolutePath();
  projectName = dir.getName();
  projectOpen = true;
  ensureProjectDirs();
  writeProjectMeta();
  loadProjectNotes();
  saveProjectNotes();
  rememberProject(projectDir);
  updateProjectTitle();
  markDirty();
  flushSettings(true);
  note("Created  " + projectName);
}

void openProjectAt(File dir) {
  if (dir == null) return;
  if (!isProjectFolder(dir)) {
    // Allow opening an empty/new folder by initializing it.
    if (dir.exists() && dir.isDirectory() && dir.list() != null && dir.list().length == 0) {
      createProjectAt(dir);
      return;
    }
    note("Not a LuckyLoop project");
    return;
  }
  closeProjectSession();
  activateProject(dir, true);
}

void requestNewProject() {
  pendingNewProject = true;
  pendingOpenProject = false;
  pendingSaveAs = false;
  selectFolder("Create LuckyLoop project folder", "projectFolderPicked");
}

void requestOpenProject() {
  pendingOpenProject = true;
  pendingNewProject = false;
  pendingSaveAs = false;
  selectFolder("Open LuckyLoop project", "projectFolderPicked");
}

void requestSaveProjectAs() {
  if (!projectOpen) {
    requestNewProject();
    return;
  }
  pendingSaveAs = true;
  pendingNewProject = false;
  pendingOpenProject = false;
  selectFolder("Save project as…", "projectFolderPicked");
}

public void projectFolderPicked(File selection) {
  boolean asNew = pendingNewProject;
  boolean asOpen = pendingOpenProject;
  boolean asSaveAs = pendingSaveAs;
  pendingNewProject = false;
  pendingOpenProject = false;
  pendingSaveAs = false;
  if (selection == null) {
    if (!projectOpen) note("No project selected");
    return;
  }
  if (asOpen) {
    openProjectAt(selection);
    return;
  }
  if (asSaveAs) {
    // Copy current settings into a new folder; loops stay in the old project.
    createProjectAt(selection);
    return;
  }
  if (asNew) {
    createProjectAt(selection);
    return;
  }
  openProjectAt(selection);
}

void chooseProjectFolder() {
  requestOpenProject();
}

void revealProject() {
  if (!projectOpen) {
    note("No project open");
    requestNewProject();
    return;
  }
  ensureProjectDirs();
  try {
    new ProcessBuilder("open", projectDir).start();
  } catch (Exception e) {
    note("Can't open the folder");
  }
}

void saveProjectNow() {
  if (!projectOpen) {
    requestNewProject();
    return;
  }
  markDirty();
  flushSettings(true);
  saveProjectNotes();
  writeProjectMeta();
  rememberProject(projectDir);
  note("Saved  " + projectName);
}

void openRecentProject(int index) {
  if (index < 0 || index >= recentProjects.size()) return;
  File dir = new File(recentProjects.get(index));
  if (!dir.isDirectory()) {
    recentProjects.remove(index);
    saveAppPrefs();
    note("Project missing");
    return;
  }
  openProjectAt(dir);
}

void bootProject() {
  loadAppPrefs();
  projectOpen = false;
  projectDir = "";
  projectName = "";
  String last = "";
  File prefs = new File(appPrefsPath());
  if (prefs.exists()) {
    try {
      JSONObject o = loadJSONObject(prefs.getAbsolutePath());
      last = o.getString("lastProject", "");
    } catch (Exception e) {
    }
  }
  if (last.length() > 0 && isProjectFolder(new File(last))) {
    openProjectAt(new File(last));
  } else {
    loadMidiMapFile();
    updateProjectTitle();
    refreshMacRecentMenu();
    note("File → New Project… to choose where loops are saved");
  }
}

void saveLayerAsync(LoopLayer layer) {
}

void binLayer(LoopLayer layer) {
}

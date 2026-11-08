#ifdef GL_ES
precision highp float;
precision highp int;
#endif

#define PROCESSING_TEXTURE_SHADER

uniform sampler2D texture;
uniform sampler2D lutM;
uniform sampler2D lutR;
uniform sampler2D lutG;
uniform sampler2D lutB;
uniform sampler2D blurFine;
uniform sampler2D blurWide;
uniform sampler2D feedbackTex;

varying vec4 vertColor;
varying vec4 vertTexCoord;

uniform vec2 texels;
uniform float exposure;
uniform float brilliance;
uniform float highlights;
uniform float shadows;
uniform float contrast;
uniform float brightness;
uniform float blackPoint;
uniform float saturation;
uniform float vibrance;
uniform float warmth;
uniform float tint;
uniform float vignette;
uniform float hueOn;
uniform float hueCos;
uniform float hueSin;
uniform float posterize;
uniform float threshold;
uniform float invert;
uniform float feedback;
uniform float sharpAmt;
uniform float noiseAmt;
uniform float clarityAmt;
uniform float stage;
uniform float coreOnly;
uniform float pixSize;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);

float curve1(sampler2D lut, float x) {
  return texture2D(lut, vec2(clamp(x, 0.001, 0.999), 0.5)).r;
}

vec3 tone(vec3 rgb) {
  rgb *= exp2(exposure * 1.5);
  float lum = dot(rgb, LUMA);
  if (abs(brilliance) > 0.004) {
    float nrm = clamp(lum / 255.0, 0.0, 1.0);
    float lift = brilliance * (1.0 - nrm) * 0.2;
    float shaped = nrm + lift + brilliance * nrm * (1.0 - nrm) * 0.5;
    shaped = clamp(shaped, 0.0, 1.4);
    if (nrm > 0.004) {
      rgb *= clamp(shaped / nrm, 0.0, 4.0);
    } else if (shaped > 0.0) {
      rgb = vec3(shaped * 255.0);
    }
    lum = dot(rgb, LUMA);
    float mx = max(rgb.r, max(rgb.g, rgb.b));
    float mn = min(rgb.r, min(rgb.g, rgb.b));
    float s = mx > 1.0 ? clamp((mx - mn) / mx, 0.0, 1.0) : 0.0;
    float vib = brilliance * 0.35 * (1.0 - s);
    rgb = mix(vec3(lum), rgb, 1.0 + vib);
    lum = dot(rgb, LUMA);
  }
  if (abs(highlights) > 0.004) {
    float w = clamp((lum - 148.0) / 107.0, 0.0, 1.0);
    float m = 1.0 + highlights * w * w * 0.95;
    rgb *= m;
    lum *= m;
  }
  if (abs(shadows) > 0.004) {
    float w = clamp((128.0 - lum) / 128.0, 0.0, 1.0);
    float add = shadows * w * w * 110.0;
    rgb += add;
    lum += add;
  }
  float ct = 1.0 + (contrast >= 0.0 ? contrast : contrast * 0.6);
  rgb = (rgb - 128.0) * ct + 128.0 + brightness * 90.0;
  if (blackPoint > 0.004) {
    float floorv = blackPoint * 48.0;
    float gain = 255.0 / (255.0 - floorv);
    rgb = (rgb - floorv) * gain;
  } else if (blackPoint < -0.004) {
    float lift = -blackPoint * 56.0;
    float keep = (255.0 - lift) / 255.0;
    rgb = rgb * keep + lift;
  }
  lum = dot(rgb, LUMA);
  rgb = mix(vec3(lum), rgb, 1.0 + saturation);
  if (abs(vibrance) > 0.004) {
    float mx = max(rgb.r, max(rgb.g, rgb.b));
    float mn = min(rgb.r, min(rgb.g, rgb.b));
    float s = mx > 1.0 ? clamp((mx - mn) / mx, 0.0, 1.0) : 0.0;
    float vib = vibrance * (1.0 - s);
    lum = dot(rgb, LUMA);
    rgb = mix(vec3(lum), rgb, 1.0 + vib);
  }
  if (abs(warmth) > 0.004) {
    rgb.r += warmth * 32.0;
    rgb.g += warmth * 8.0;
    rgb.b -= warmth * 36.0;
  }
  if (abs(tint) > 0.004) {
    rgb.r += tint * 16.0;
    rgb.g -= tint * 28.0;
    rgb.b += tint * 16.0;
  }
  return rgb;
}

vec3 spatial(vec3 c, vec2 uv) {
  if (sharpAmt > 0.004 || noiseAmt > 0.004) {
    vec3 f = texture2D(blurFine, uv).rgb * 255.0;
    c += (f - c) * noiseAmt + (c - f) * sharpAmt;
  }
  if (abs(clarityAmt) > 0.004) {
    vec3 f = texture2D(blurWide, uv).rgb * 255.0;
    float lum = dot(c, LUMA);
    float mid = 1.0 - clamp(abs(lum / 255.0 - 0.5) * 2.0, 0.0, 1.0);
    float k = clarityAmt * (0.4 + 0.6 * mid);
    c += (c - f) * k;
  }
  return c;
}

vec3 finish(vec3 rgb, vec2 uv) {
  if (abs(vignette) > 0.004) {
    float dist = length((uv - 0.5) * 2.0);
    float edge = clamp((dist - 0.42) / 0.7, 0.0, 1.0);
    edge = edge * edge;
    if (vignette >= 0.0) rgb *= 1.0 - edge * vignette;
    else {
      float a = edge * -vignette;
      rgb = rgb * (1.0 - a) + 255.0 * a;
    }
  }
  if (hueOn > 0.5) {
    float r = rgb.r;
    float g = rgb.g;
    float b = rgb.b;
    rgb.r = r * (0.213 + hueCos * 0.787 - hueSin * 0.213)
      + g * (0.715 - hueCos * 0.715 - hueSin * 0.715)
      + b * (0.072 - hueCos * 0.072 + hueSin * 0.928);
    rgb.g = r * (0.213 - hueCos * 0.213 + hueSin * 0.143)
      + g * (0.715 + hueCos * 0.285 + hueSin * 0.140)
      + b * (0.072 - hueCos * 0.072 - hueSin * 0.283);
    rgb.b = r * (0.213 - hueCos * 0.213 - hueSin * 0.787)
      + g * (0.715 - hueCos * 0.715 + hueSin * 0.715)
      + b * (0.072 + hueCos * 0.928 + hueSin * 0.072);
  }
  if (posterize >= 2.0) {
    float stepv = max(1.0, floor(255.0 / (posterize - 1.0)));
    rgb = floor(clamp(rgb, 0.0, 255.0) / stepv) * stepv;
  }
  if (threshold > 0.02) {
    float on = step(threshold * 255.0, dot(rgb, LUMA));
    rgb = vec3(on * 255.0);
  }
  if (invert > 0.5) rgb = 255.0 - rgb;
  if (feedback > 0.001) {
    vec3 prev = texture2D(feedbackTex, uv).rgb * 255.0;
    rgb = rgb * (1.0 - feedback) + prev * feedback;
  }
  return rgb;
}

void main() {
  vec2 uv = vertTexCoord.st;
  vec3 rgb;
  if (stage < 0.5) {
    vec2 suv = uv;
    if (pixSize > 1.5) {
      vec2 g = pixSize * texels;
      suv = (floor(uv / g) + 0.5) * g;
    }
    rgb = texture2D(texture, suv).rgb * 255.0;
    rgb = tone(rgb);
    rgb = clamp(rgb, 0.0, 255.0);
    rgb = vec3(
      curve1(lutR, curve1(lutM, rgb.r / 255.0)),
      curve1(lutG, curve1(lutM, rgb.g / 255.0)),
      curve1(lutB, curve1(lutM, rgb.b / 255.0))
    ) * 255.0;
    if (coreOnly > 0.5) {
      gl_FragColor = vec4(rgb / 255.0, 1.0);
      return;
    }
  } else {
    rgb = texture2D(texture, uv).rgb * 255.0;
    rgb = spatial(rgb, uv);
    rgb = clamp(rgb, 0.0, 255.0);
  }
  rgb = clamp(finish(rgb, uv), 0.0, 255.0) / 255.0;
  gl_FragColor = vec4(rgb, 1.0);
}

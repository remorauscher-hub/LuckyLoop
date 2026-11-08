#ifdef GL_ES
precision highp float;
precision highp int;
#endif

#define PROCESSING_TEXTURE_SHADER

uniform sampler2D texture;
varying vec4 vertTexCoord;
uniform vec2 texels;
uniform vec2 dir;
uniform float radius;

void main() {
  vec2 uv = vertTexCoord.st;
  float rad = clamp(radius, 0.0, 8.0);
  float span = rad * 2.0 + 1.0;
  vec3 acc = vec3(0.0);
  for (int i = -8; i <= 8; i++) {
    float fi = float(i);
    float w = step(abs(fi), rad + 0.01);
    acc += texture2D(texture, uv + dir * texels * fi).rgb * w;
  }
  gl_FragColor = vec4(acc / span, 1.0);
}

#version 320 es

precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;

layout(location = 0) out vec4 fragColor;

void main() {
    vec4 color = texture(tex, v_texcoord);
    fragColor = vec4(color.r, color.g * 0.27, 0.0, color.a);
}

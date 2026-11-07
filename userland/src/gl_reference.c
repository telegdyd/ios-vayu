/* Small, independently checked A640 reference submissions for Metal roadmap task 4.
 * Link directly to Mesa OSMesa; never presents or touches the window server.
 * Usage: gl_reference clear|texture|mrt|blend|compute
 * Mesa's FD_RD_DUMP captures all submitted BOs in /tmp/metal4_CASE_*.rd.
 */
#include <GLES3/gl31.h>
#include <GL/osmesa.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#ifndef OSMESA_ES_PROFILE
#define OSMESA_ES_PROFILE 0x38
#endif

static void fail(const char *message)
{
    fprintf(stderr, "gl_reference: FAIL %s (GL error 0x%x)\n", message, glGetError());
    exit(1);
}

static GLuint shader(GLenum type, const char *source)
{
    GLuint s = glCreateShader(type);
    GLint ok;
    char log[4096];
    glShaderSource(s, 1, &source, NULL);
    glCompileShader(s);
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        glGetShaderInfoLog(s, sizeof(log), NULL, log);
        fprintf(stderr, "%s\n", log);
        fail("shader compile");
    }
    return s;
}

static GLuint program(const char *fragment, int compute)
{
    const char *vertex = "#version 300 es\n"
        "void main(){vec2 p[3]=vec2[3](vec2(-1,-1),vec2(3,-1),vec2(-1,3));"
        "gl_Position=vec4(p[gl_VertexID],0,1);}";
    GLuint p = glCreateProgram();
    GLint ok;
    char log[4096];
    if (!compute) glAttachShader(p, shader(GL_VERTEX_SHADER, vertex));
    glAttachShader(p, shader(compute ? GL_COMPUTE_SHADER : GL_FRAGMENT_SHADER, fragment));
    glLinkProgram(p);
    glGetProgramiv(p, GL_LINK_STATUS, &ok);
    if (!ok) {
        glGetProgramInfoLog(p, sizeof(log), NULL, log);
        fprintf(stderr, "%s\n", log);
        fail("program link");
    }
    glUseProgram(p);
    return p;
}

static GLuint texture(int size, const void *pixels)
{
    GLuint t;
    glGenTextures(1, &t);
    glBindTexture(GL_TEXTURE_2D, t);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, size, size, 0, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    return t;
}

static void pixels(unsigned attachment, const unsigned char expected[4])
{
    unsigned char image[32*32*4];
    glReadBuffer(GL_COLOR_ATTACHMENT0 + attachment);
    glReadPixels(0, 0, 32, 32, GL_RGBA, GL_UNSIGNED_BYTE, image);
    for (unsigned i = 0; i < sizeof(image); i++) {
        if (abs((int)image[i] - expected[i % 4]) > 1) {
            fprintf(stderr, "attachment %u byte %u: got %u expected %u\n",
                    attachment, i, image[i], expected[i % 4]);
            fail("pixel comparison");
        }
    }
    printf("attachment %u: all 1024 pixels match [%u,%u,%u,%u] (+/-1)\n",
           attachment, expected[0], expected[1], expected[2], expected[3]);
}

int main(int argc, char **argv)
{
    if (argc != 2 || (strcmp(argv[1], "clear") && strcmp(argv[1], "texture") &&
        strcmp(argv[1], "mrt") && strcmp(argv[1], "blend") && strcmp(argv[1], "compute"))) {
        fprintf(stderr, "usage: gl_reference clear|texture|mrt|blend|compute\n");
        return 2;
    }
    char name[64];
    snprintf(name, sizeof(name), "metal4_%s", argv[1]);
    setenv("FD_RD_DUMP", "enable,full", 1);
    setenv("FD_RD_DUMP_TESTNAME", name, 1);
    const int attributes[] = {OSMESA_FORMAT, OSMESA_RGBA, OSMESA_PROFILE,
        OSMESA_ES_PROFILE, OSMESA_CONTEXT_MAJOR_VERSION, 3,
        OSMESA_CONTEXT_MINOR_VERSION, 1, 0};
    unsigned char window[16*16*4];
    OSMesaContext context = OSMesaCreateContextAttribs(attributes, NULL);
    if (!context || !OSMesaMakeCurrent(context, window, GL_UNSIGNED_BYTE, 16, 16))
        fail("OSMesa ES 3.1 context");
    const char *renderer = (const char *)glGetString(GL_RENDERER);
    printf("case=%s renderer=%s version=%s\n", argv[1], renderer, glGetString(GL_VERSION));
    if (!renderer || !strstr(renderer, "640")) fail("requires hardware A640 renderer");

    if (!strcmp(argv[1], "compute")) {
        uint32_t initial[64] = {0};
        GLuint buffer;
        program("#version 310 es\nlayout(local_size_x=8) in;"
            "layout(std430,binding=0) buffer Output {uint data[];};"
            "void main(){uint i=gl_GlobalInvocationID.x;data[i]=i*3u+7u;}", 1);
        glGenBuffers(1, &buffer);
        glBindBuffer(GL_SHADER_STORAGE_BUFFER, buffer);
        glBufferData(GL_SHADER_STORAGE_BUFFER, sizeof(initial), initial, GL_DYNAMIC_READ);
        glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, buffer);
        glDispatchCompute(8, 1, 1);
        glMemoryBarrier(GL_BUFFER_UPDATE_BARRIER_BIT);
        glFinish();
        const uint32_t *out = glMapBufferRange(GL_SHADER_STORAGE_BUFFER, 0, sizeof(initial), GL_MAP_READ_BIT);
        if (!out) fail("compute map");
        for (unsigned i = 0; i < 64; i++) if (out[i] != i*3+7) fail("compute comparison");
        glUnmapBuffer(GL_SHADER_STORAGE_BUFFER);
        printf("compute: all 64 uints match i*3+7\n");
    } else {
        GLuint fbo;
        glGenFramebuffers(1, &fbo);
        glBindFramebuffer(GL_FRAMEBUFFER, fbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture(32, NULL), 0);
        int mrt = !strcmp(argv[1], "mrt");
        if (mrt) {
            GLenum buffers[] = {GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1};
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT1, GL_TEXTURE_2D, texture(32, NULL), 0);
            glDrawBuffers(2, buffers);
        }
        if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) fail("framebuffer");
        glViewport(0, 0, 32, 32);
        glClearColor(0, 0, 1, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        unsigned char expected[] = {0, 0, 255, 255};
        if (!strcmp(argv[1], "texture")) {
            const unsigned char texel[] = {51, 102, 153, 255};
            program("#version 300 es\nprecision highp float;uniform sampler2D tex;"
                "out vec4 color;void main(){color=texture(tex,vec2(0.5));}", 0);
            glActiveTexture(GL_TEXTURE0);
            texture(1, texel);
            memcpy(expected, texel, 4);
        } else if (mrt) {
            program("#version 300 es\nprecision highp float;"
                "layout(location=0) out vec4 a;layout(location=1) out vec4 b;"
                "void main(){a=vec4(1,0,0,1);b=vec4(0,1,0,1);}", 0);
            memcpy(expected, (unsigned char[]){255,0,0,255}, 4);
        } else if (!strcmp(argv[1], "blend")) {
            program("#version 300 es\nprecision highp float;out vec4 color;"
                "void main(){color=vec4(1,0,0,0.5);}", 0);
            glEnable(GL_BLEND);
            glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
            memcpy(expected, (unsigned char[]){128,0,128,255}, 4);
        }
        if (strcmp(argv[1], "clear")) glDrawArrays(GL_TRIANGLES, 0, 3);
        glFinish();
        pixels(0, expected);
        if (mrt) pixels(1, (unsigned char[]){0,255,0,255});
    }
    if (glGetError() != GL_NO_ERROR) fail("final GL status");
    OSMesaDestroyContext(context);
    printf("gl_reference: PASS %s\n", argv[1]);
    return 0;
}

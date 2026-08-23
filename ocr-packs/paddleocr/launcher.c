#include <libgen.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    uint32_t executable_path_size = PATH_MAX;
    char executable_path[PATH_MAX];
    if (_NSGetExecutablePath(executable_path, &executable_path_size) != 0) {
        fprintf(stderr, "PaddleOCR launcher failed: executable path is too long\n");
        return 70;
    }

    char resolved_path[PATH_MAX];
    if (realpath(executable_path, resolved_path) == NULL) {
        perror("PaddleOCR launcher failed");
        return 70;
    }

    char bin_path[PATH_MAX];
    char root_path[PATH_MAX];
    strncpy(bin_path, resolved_path, sizeof(bin_path) - 1);
    bin_path[sizeof(bin_path) - 1] = '\0';
    strncpy(root_path, dirname(bin_path), sizeof(root_path) - 1);
    root_path[sizeof(root_path) - 1] = '\0';
    strncpy(root_path, dirname(root_path), sizeof(root_path) - 1);
    root_path[sizeof(root_path) - 1] = '\0';

    char python_path[PATH_MAX];
    char adapter_path[PATH_MAX];
    char models_path[PATH_MAX];
    snprintf(python_path, sizeof(python_path), "%s/runtime/bin/python3", root_path);
    snprintf(adapter_path, sizeof(adapter_path), "%s/adapter/adapter.py", root_path);
    snprintf(models_path, sizeof(models_path), "%s/models", root_path);

    setenv("AI_SCREENSHOT_PADDLE_MODELS_DIR", models_path, 1);
    setenv("PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK", "True", 1);
    setenv("PADDLE_PDX_MODEL_SOURCE", "BOS", 1);
    setenv("PYTHONNOUSERSITE", "1", 1);
    setenv("PYTHONDONTWRITEBYTECODE", "1", 1);

    char **child_argv = calloc((size_t)argc + 2, sizeof(char *));
    if (child_argv == NULL) {
        fprintf(stderr, "PaddleOCR launcher failed: out of memory\n");
        return 71;
    }
    child_argv[0] = python_path;
    child_argv[1] = adapter_path;
    for (int index = 1; index < argc; index++) {
        child_argv[index + 1] = argv[index];
    }
    child_argv[argc + 1] = NULL;

    execv(python_path, child_argv);
    perror("PaddleOCR launcher failed");
    free(child_argv);
    return 72;
}

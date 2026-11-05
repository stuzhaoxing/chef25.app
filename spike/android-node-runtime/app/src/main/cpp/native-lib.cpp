#include <android/log.h>
#include <fcntl.h>
#include <jni.h>
#include <unistd.h>

#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <stdexcept>
#include <string>
#include <vector>

namespace node {
int Start(int argc, char* argv[]);
}

namespace {
constexpr const char* kLogTag = "Chef25NodeSpike";

class JniString {
public:
    JniString(JNIEnv* env, jstring value)
        : env_(env), value_(value), chars_(env->GetStringUTFChars(value, nullptr)) {
        if (chars_ == nullptr) {
            throw std::runtime_error("GetStringUTFChars returned null");
        }
    }

    ~JniString() {
        env_->ReleaseStringUTFChars(value_, chars_);
    }

    JniString(const JniString&) = delete;
    JniString& operator=(const JniString&) = delete;

    const char* get() const {
        return chars_;
    }

private:
    JNIEnv* env_;
    jstring value_;
    const char* chars_;
};

struct NodeArguments {
    std::vector<std::string> values;
    std::vector<char*> pointers;
};

NodeArguments CopyArguments(JNIEnv* env, jobjectArray arguments) {
    NodeArguments result;
    const jsize count = env->GetArrayLength(arguments);
    result.values.reserve(static_cast<size_t>(count));
    result.pointers.reserve(static_cast<size_t>(count));

    for (jsize index = 0; index < count; ++index) {
        auto value = static_cast<jstring>(env->GetObjectArrayElement(arguments, index));
        {
            JniString utf8(env, value);
            result.values.emplace_back(utf8.get());
        }
        env->DeleteLocalRef(value);
    }

    for (std::string& value : result.values) {
        result.pointers.push_back(value.data());
    }
    return result;
}
}  // namespace

extern "C" JNIEXPORT jint JNICALL
Java_com_chef25_mobile_nodespike_MainActivity_startNodeWithArguments(
    JNIEnv* env,
    jobject,
    jobjectArray arguments,
    jstring nodePath) {
    JniString nodePathUtf8(env, nodePath);
    setenv("NODE_PATH", nodePathUtf8.get(), 1);

    const std::string outputPath =
        std::string(nodePathUtf8.get()) + "/node-output.log";
    const int outputFd = open(
        outputPath.c_str(),
        O_CREAT | O_WRONLY | O_TRUNC,
        0600);
    if (outputFd >= 0) {
        setvbuf(stdout, nullptr, _IOLBF, 0);
        setvbuf(stderr, nullptr, _IOLBF, 0);
        dup2(outputFd, STDOUT_FILENO);
        dup2(outputFd, STDERR_FILENO);
        close(outputFd);
    } else {
        __android_log_print(
            ANDROID_LOG_WARN,
            kLogTag,
            "Could not open Node output log: %s",
            outputPath.c_str());
    }

    NodeArguments copied = CopyArguments(env, arguments);
    __android_log_print(
        ANDROID_LOG_INFO,
        kLogTag,
        "Starting in-process Node.js runtime with %zu arguments",
        copied.pointers.size());

    const int result = node::Start(
        static_cast<int>(copied.pointers.size()),
        copied.pointers.data());
    __android_log_print(ANDROID_LOG_INFO, kLogTag, "node::Start returned %d", result);
    return result;
}

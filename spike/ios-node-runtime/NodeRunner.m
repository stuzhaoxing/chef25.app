#import "NodeRunner.h"

#include <stdlib.h>
#include <string.h>

static void Chef25RunNode(void *context) {
    @autoreleasepool {
        NSArray<NSString *> *values = (__bridge NSArray<NSString *> *)context;
        NSString *projectPath = values[0];
        NSString *dataRoot = values[1];
        NSString *bootstrapPath = [values[0] stringByDeletingLastPathComponent];
        bootstrapPath = [bootstrapPath stringByAppendingPathComponent:
            @".chef25-runtime/WebAssemblyTiktokenBootstrap.cjs"];
        NSString *configPath = [dataRoot stringByAppendingPathComponent:@"config.yaml"];
        NSString *portArgument = @"--port=8123";
        NSString *ipv4Argument = @"--enableIPv4=true";
        NSString *ipv6Argument = @"--enableIPv6=false";
        NSString *listenArgument = @"--listen=false";
        NSString *browserArgument = @"--browserLaunchEnabled=false";
        NSString *whitelistArgument = @"--whitelist=false";
        NSString *configArgument = [NSString stringWithFormat:@"--configPath=%@", configPath];
        NSString *dataArgument = [NSString stringWithFormat:@"--dataRoot=%@", dataRoot];
        NSArray<NSString *> *arguments = @[
            @"node",
            @"--require",
            bootstrapPath,
            projectPath,
            portArgument,
            ipv4Argument,
            ipv6Argument,
            listenArgument,
            browserArgument,
            whitelistArgument,
            configArgument,
            dataArgument,
        ];

        NSUInteger bufferSize = 1;
        for (NSString *argument in arguments) {
            bufferSize += [argument lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 1;
        }

        char *buffer = calloc(bufferSize, sizeof(char));
        char **argv = calloc(arguments.count, sizeof(char *));
        char *position = buffer;

        for (NSUInteger index = 0; index < arguments.count; index++) {
            const char *value = arguments[index].UTF8String;
            size_t length = strlen(value);
            memcpy(position, value, length);
            argv[index] = position;
            position += length + 1;
        }

        NSLog(@"[Chef25NodeSpike] starting Node.js from %@ with data root %@", projectPath, dataRoot);
        int result = node_start((int)arguments.count, argv);
        NSLog(@"[Chef25NodeSpike] node_start returned %d", result);

        free(argv);
        free(buffer);
    }
}

void Chef25StartNode(const char *projectPath, const char *dataRoot) {
    NSArray<NSString *> *values = @[
        [NSString stringWithUTF8String:projectPath],
        [NSString stringWithUTF8String:dataRoot],
    ];
    NSThread *thread = [[NSThread alloc] initWithBlock:^{
        Chef25RunNode((__bridge void *)values);
    }];
    thread.name = @"Chef25 Node.js";
    [thread setStackSize:4 * 1024 * 1024];
    [thread start];
}

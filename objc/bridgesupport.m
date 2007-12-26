// bridgesupport.m
//  Nu reader for Apple BridgeSupport files.
//
//  Copyright (c) 2007 Tim Burks, Neon Design Technology, Inc.

#import <Cocoa/Cocoa.h>
#import <dlfcn.h>
#import "bridgesupport.h"
#import "extensions.h"
#import "symbol.h"

@implementation NuBridgeSupport

+ (void)importLibrary:(NSString *) libraryPath
{
    //NSLog(@"importing library %@", libraryPath);
    dlopen([libraryPath cStringUsingEncoding:NSUTF8StringEncoding], RTLD_LAZY | RTLD_GLOBAL);
}

+ (void)importFramework:(NSString *) framework fromPath:(NSString *) path intoDictionary:(NSMutableDictionary *) BridgeSupport
{
    NSMutableDictionary *frameworks = [BridgeSupport valueForKey:@"frameworks"];
    if ([frameworks valueForKey:framework])
        return;
    else
        [frameworks setValue:framework forKey:framework];

    NSString *xmlPath;                            // constants, enums, functions, and more are described in an XML file.
    NSString *dylibPath;                          // sometimes a dynamic library is included to provide implementations of inline functions.

    if (path) {
        xmlPath = [NSString stringWithFormat:@"%@/Resources/BridgeSupport/%@.bridgesupport", path, framework];
        dylibPath = [NSString stringWithFormat:@"%@/Resources/BridgeSupport/%@.dylib", path, framework];
    }
    else {
        xmlPath = [NSString stringWithFormat:@"/System/Library/Frameworks/%@.framework/Resources/BridgeSupport/%@.bridgesupport", framework, framework];
        dylibPath = [NSString stringWithFormat:@"/System/Library/Frameworks/%@.framework/Resources/BridgeSupport/%@.dylib", framework, framework];
    }

    if ([NSFileManager fileExistsNamed:dylibPath])
        [self importLibrary:dylibPath];

    NSMutableDictionary *constants = [BridgeSupport valueForKey:@"constants"];
    NSMutableDictionary *enums =     [BridgeSupport valueForKey:@"enums"];
    NSMutableDictionary *functions = [BridgeSupport valueForKey:@"functions"];

    NSXMLDocument *xmlDocument = [[NSXMLDocument alloc] initWithContentsOfURL:[NSURL fileURLWithPath:xmlPath] options:0 error:nil];
    if (xmlDocument) {
        id node;
        NSEnumerator *childEnumerator = [[[xmlDocument rootElement] children] objectEnumerator];
        while (node = [childEnumerator nextObject]) {
            if ([[node name] isEqual:@"depends_on"]) {
                id fileName = [[node attributeForName:@"path"] stringValue];
                id frameworkName = [[[fileName lastPathComponent] componentsSeparatedByString:@"."] objectAtIndex:0];
                [NuBridgeSupport importFramework:frameworkName fromPath:fileName intoDictionary:BridgeSupport];
            }
            else if ([[node name] isEqual:@"constant"]) {
                [constants setValue:[[node attributeForName:@"type"] stringValue]
                    forKey:[[node attributeForName:@"name"] stringValue]];
            }
            else if ([[node name] isEqual:@"enum"]) {
                [enums setValue:[NSNumber numberWithInt:[[[node attributeForName:@"value"] stringValue] intValue]]
                    forKey:[[node attributeForName:@"name"] stringValue]];
            }
            else if ([[node name] isEqual:@"function"]) {
                id name = [[node attributeForName:@"name"] stringValue];
                id argumentTypes = [NSMutableString string];
                id returnType = @"v";
                id child;
                NSEnumerator *nodeChildEnumerator = [[node children] objectEnumerator];
                while (child = [nodeChildEnumerator nextObject]) {
                    if ([[child name] isEqual:@"arg"]) {
                        id typeModifier = [child attributeForName:@"type_modifier"];
                        if (typeModifier) {
                            [argumentTypes appendString:[typeModifier stringValue]];
                        }
                        [argumentTypes appendString:[[child attributeForName:@"type"] stringValue]];
                    }
                    else if ([[child name] isEqual:@"retval"]) {
                        returnType = [[child attributeForName:@"type"] stringValue];
                    }
                    else {
                        NSLog(@"unrecognized type #{[child XMLString]}");
                    }
                }
                id signature = [NSString stringWithFormat:@"%@%@", returnType, argumentTypes];
                [functions setValue:signature forKey:name];
            }
        }
    }
    else {
        // don't complain about missing bridge support files...
        //NSString *reason = [NSString stringWithFormat:@"unable to find BridgeSupport file for %@", framework];
        //[[NSException exceptionWithName:@"NuBridgeSupportMissing" reason:reason userInfo:nil] raise];
    }
}

+ (void) prune
{
    NuSymbolTable *symbolTable = [NuSymbolTable sharedSymbolTable];
    id BridgeSupport = [[symbolTable symbolWithString:@"BridgeSupport"] value];
    [[BridgeSupport objectForKey:@"frameworks"] removeAllObjects];

    id key;
    for (int i = 0; i < 3; i++) {
        id dictionary = [BridgeSupport objectForKey:(i == 0) ? @"constants" : (i == 1) ? @"enums" : @"functions"];
        id keyEnumerator = [[dictionary allKeys] objectEnumerator];
        while (key = [keyEnumerator nextObject]) {
            if (![symbolTable lookup:[key cStringUsingEncoding:NSUTF8StringEncoding]])
                [dictionary removeObjectForKey:key];
        }
    }
}

+ (NSString *) stringValue
{
    NuSymbolTable *symbolTable = [NuSymbolTable sharedSymbolTable];
    id BridgeSupport = [[symbolTable symbolWithString:@"BridgeSupport"] value];

    id result = [NSMutableString stringWithString:@"(global BridgeSupport\n"];
    id d, keyEnumerator, key;

    [result appendString:@"        (dict\n"];
    d = [BridgeSupport objectForKey:@"constants"];
    [result appendString:@"             constants:\n"];
    [result appendString:@"             (dict"];
    keyEnumerator = [[[d allKeys] sortedArrayUsingSelector:@selector(compare:)] objectEnumerator];
    while (key = [keyEnumerator nextObject]) {
        [result appendString:[NSString stringWithFormat:@"\n                  \"%@\" \"%@\"", key, [d objectForKey:key]]];
    }
    [result appendString:@")\n"];

    d = [BridgeSupport objectForKey:@"enums"];
    [result appendString:@"             enums:\n"];
    [result appendString:@"             (dict"];
    keyEnumerator = [[[d allKeys] sortedArrayUsingSelector:@selector(compare:)] objectEnumerator];
    while (key = [keyEnumerator nextObject]) {
        [result appendString:[NSString stringWithFormat:@"\n                  \"%@\" %@", key, [d objectForKey:key]]];
    }
    [result appendString:@")\n"];

    d = [BridgeSupport objectForKey:@"functions"];
    [result appendString:@"             functions:\n"];
    [result appendString:@"             (dict"];
    keyEnumerator = [[[d allKeys] sortedArrayUsingSelector:@selector(compare:)] objectEnumerator];
    while (key = [keyEnumerator nextObject]) {
        [result appendString:[NSString stringWithFormat:@"\n                  \"%@\" \"%@\"", key, [d objectForKey:key]]];
    }
    [result appendString:@")\n"];

    d = [BridgeSupport objectForKey:@"frameworks"];
    [result appendString:@"             frameworks:\n"];
    [result appendString:@"             (dict"];
    keyEnumerator = [[[d allKeys] sortedArrayUsingSelector:@selector(compare:)] objectEnumerator];
    while (key = [keyEnumerator nextObject]) {
        [result appendString:[NSString stringWithFormat:@"\n                  \"%@\" \"%@\"", key, [d objectForKey:key]]];
    }
    [result appendString:@")))\n"];
    return result;
}

@end

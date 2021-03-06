//
//  YamahaImporter.h
//  purefm
//
//  Created by Paul Forgey on 5/21/20.
//  Copyright © 2020 Paul Forgey. All rights reserved.
//

#import "Importer.h"

NS_ASSUME_NONNULL_BEGIN

@interface YamahaPatch : ImportedPatch

@property NSString *name;

@end

@interface YamahaImporter : Importer

@property (nonatomic,readonly) NSArray< ImportedPatch * > *patches;

+ (YamahaImporter *)importerWithData:(NSData *)data error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

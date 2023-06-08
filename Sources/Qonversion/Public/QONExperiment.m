//
//  QONExperiment.m
//  Qonversion
//
//  Created by Suren Sarkisyan on 08.06.2023.
//  Copyright © 2023 Qonversion Inc. All rights reserved.
//

#import "QONExperiment.h"

@implementation QONExperiment

- (instancetype)initWithIdentifier:(NSString *)identifier
                              name:(NSString *)name
                             group:(QONExperimentGroup *)group {
  self = [super init];
  
  if (self) {
    _identifier = identifier;
    _name = name;
    _group = group;
  }
  
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super init];
  
  if (self) {
    _identifier = [coder decodeObjectForKey:NSStringFromSelector(@selector(identifier))];
    _name = [coder decodeObjectForKey:NSStringFromSelector(@selector(name))];
    _group = [coder decodeObjectForKey:NSStringFromSelector(@selector(group))];
  }
  
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [coder encodeObject:_identifier forKey:NSStringFromSelector(@selector(identifier))];
  [coder encodeObject:_name forKey:NSStringFromSelector(@selector(name))];
  [coder encodeObject:_group forKey:NSStringFromSelector(@selector(group))];
}

@end

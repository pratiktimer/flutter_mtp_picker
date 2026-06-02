#import "FlutterMtpPickerPlugin.h"

#import <ImageCaptureCore/ImageCaptureCore.h>

static NSString *const kChannelName = @"flutter_mtp_picker";
static NSString *const kRootObjectId = @"ROOT";

@interface FlutterMtpPickerPlugin () <ICDeviceBrowserDelegate, ICCameraDeviceDelegate, ICCameraDeviceDownloadDelegate>
@property(nonatomic, strong) ICDeviceBrowser *deviceBrowser;
@property(nonatomic, strong) NSMutableDictionary<NSString *, ICCameraDevice *> *devicesById;
@property(nonatomic, strong) NSMutableDictionary<NSString *, ICCameraItem *> *itemsById;
@property(nonatomic, strong) NSMutableArray *pendingDeviceResults;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray *> *pendingSessionBlocks;
@property(nonatomic, strong) NSMutableDictionary<NSString *, id> *pendingDownloads;
@property(nonatomic, assign) BOOL didEnumerateInitialDevices;
@end

@implementation FlutterMtpPickerPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:kChannelName
                                  binaryMessenger:[registrar messenger]];
  FlutterMtpPickerPlugin *instance = [[FlutterMtpPickerPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _devicesById = [NSMutableDictionary dictionary];
    _itemsById = [NSMutableDictionary dictionary];
    _pendingDeviceResults = [NSMutableArray array];
    _pendingSessionBlocks = [NSMutableDictionary dictionary];
    _pendingDownloads = [NSMutableDictionary dictionary];
  }
  return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([@"getDevices" isEqualToString:call.method]) {
    [self getDevices:result];
  } else if ([@"listChildren" isEqualToString:call.method]) {
    NSDictionary *arguments = [self dictionaryArguments:call.arguments result:result method:call.method];
    if (arguments != nil) {
      [self listChildren:arguments result:result];
    }
  } else if ([@"listMediaFiles" isEqualToString:call.method]) {
    NSDictionary *arguments = [self dictionaryArguments:call.arguments result:result method:call.method];
    if (arguments != nil) {
      [self listMediaFiles:arguments result:result];
    }
  } else if ([@"copyFileToLocal" isEqualToString:call.method]) {
    NSDictionary *arguments = [self dictionaryArguments:call.arguments result:result method:call.method];
    if (arguments != nil) {
      [self copyFileToLocal:arguments result:result];
    }
  } else if ([@"copyFilesToLocal" isEqualToString:call.method]) {
    NSDictionary *arguments = [self dictionaryArguments:call.arguments result:result method:call.method];
    if (arguments != nil) {
      [self copyFilesToLocal:arguments result:result];
    }
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (NSDictionary *)dictionaryArguments:(id)arguments
                               result:(FlutterResult)result
                               method:(NSString *)method {
  if (![arguments isKindOfClass:[NSDictionary class]]) {
    result([FlutterError errorWithCode:@"invalid_arguments"
                               message:[NSString stringWithFormat:@"%@ expects an argument map.", method]
                               details:nil]);
    return nil;
  }
  return (NSDictionary *)arguments;
}

- (void)getDevices:(FlutterResult)result {
  [self startBrowserIfNeeded];

  if (self.didEnumerateInitialDevices) {
    result([self encodedDevices]);
    return;
  }

  [self.pendingDeviceResults addObject:[result copy]];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
                   [self flushPendingDeviceResults];
                 });
}

- (void)listChildren:(NSDictionary *)arguments result:(FlutterResult)result {
  NSString *deviceId = [self stringValue:arguments[@"deviceId"]];
  NSString *objectId = [self stringValue:arguments[@"objectId"]];
  if (deviceId.length == 0 || objectId.length == 0) {
    result([self invalidArguments:@"listChildren requires deviceId and objectId."]);
    return;
  }

  ICCameraDevice *device = self.devicesById[deviceId];
  if (device == nil) {
    result([self deviceNotFound:deviceId]);
    return;
  }

  [self openDevice:device deviceId:deviceId completion:^(NSError *error) {
    if (error != nil) {
      result([self flutterError:@"macos_image_capture_error"
                        message:error.localizedDescription
                        details:@(error.code)]);
      return;
    }

    NSArray<ICCameraItem *> *children = [self childrenForObjectId:objectId device:device deviceId:deviceId];
    if (children == nil) {
      result([self objectNotFound:objectId]);
      return;
    }

    NSMutableArray *encoded = [NSMutableArray array];
    for (ICCameraItem *item in children) {
      [self indexItemTree:item deviceId:deviceId prefix:objectId];
      [encoded addObject:[self encodedObject:item deviceId:deviceId]];
    }
    result(encoded);
  }];
}

- (void)listMediaFiles:(NSDictionary *)arguments result:(FlutterResult)result {
  NSString *deviceId = [self stringValue:arguments[@"deviceId"]];
  NSString *folderId = [self stringValue:arguments[@"folderId"]];
  NSArray *extensions = [arguments[@"extensions"] isKindOfClass:[NSArray class]]
      ? arguments[@"extensions"]
      : nil;
  if (deviceId.length == 0 || folderId.length == 0 || extensions == nil) {
    result([self invalidArguments:@"listMediaFiles requires deviceId, folderId, and extensions."]);
    return;
  }

  ICCameraDevice *device = self.devicesById[deviceId];
  if (device == nil) {
    result([self deviceNotFound:deviceId]);
    return;
  }

  NSSet<NSString *> *normalizedExtensions = [self normalizedExtensions:extensions];
  [self openDevice:device deviceId:deviceId completion:^(NSError *error) {
    if (error != nil) {
      result([self flutterError:@"macos_image_capture_error"
                        message:error.localizedDescription
                        details:@(error.code)]);
      return;
    }

    NSArray<ICCameraItem *> *children = [self childrenForObjectId:folderId device:device deviceId:deviceId];
    if (children == nil) {
      result([self objectNotFound:folderId]);
      return;
    }

    NSMutableArray *files = [NSMutableArray array];
    for (ICCameraItem *item in children) {
      [self appendMediaFilesFromItem:item
                            deviceId:deviceId
                              prefix:folderId
                          extensions:normalizedExtensions
                              output:files];
    }
    result(files);
  }];
}

- (void)copyFileToLocal:(NSDictionary *)arguments result:(FlutterResult)result {
  NSString *deviceId = [self stringValue:arguments[@"deviceId"]];
  NSString *fileId = [self stringValue:arguments[@"fileId"]];
  NSString *destinationPath = [self stringValue:arguments[@"destinationPath"]];
  if (deviceId.length == 0 || fileId.length == 0 || destinationPath.length == 0) {
    result([self invalidArguments:@"copyFileToLocal requires deviceId, fileId, and destinationPath."]);
    return;
  }

  ICCameraDevice *device = self.devicesById[deviceId];
  ICCameraItem *item = self.itemsById[fileId];
  if (device == nil) {
    result([self deviceNotFound:deviceId]);
    return;
  }
  if (![item isKindOfClass:[ICCameraFile class]]) {
    result([self objectNotFound:fileId]);
    return;
  }

  [self openDevice:device deviceId:deviceId completion:^(NSError *error) {
    if (error != nil) {
      result([self flutterError:@"macos_image_capture_error"
                        message:error.localizedDescription
                        details:@(error.code)]);
      return;
    }
    [self requestDownloadFile:(ICCameraFile *)item
                       device:device
              destinationPath:destinationPath
                       result:result];
  }];
}

- (void)copyFilesToLocal:(NSDictionary *)arguments result:(FlutterResult)result {
  NSString *deviceId = [self stringValue:arguments[@"deviceId"]];
  NSDictionary *files = [arguments[@"files"] isKindOfClass:[NSDictionary class]]
      ? arguments[@"files"]
      : nil;
  if (deviceId.length == 0 || files == nil) {
    result([self invalidArguments:@"copyFilesToLocal requires deviceId and a string map named files."]);
    return;
  }

  __block NSMutableArray<NSString *> *copiedPaths = [NSMutableArray array];
  NSArray<NSString *> *fileIds = files.allKeys;
  __block NSUInteger index = 0;
  __block void (^copyNext)(void);

  copyNext = ^{
    if (index >= fileIds.count) {
      result(copiedPaths);
      return;
    }

    NSString *fileId = fileIds[index++];
    NSString *destinationPath = [self stringValue:files[fileId]];
    if (destinationPath.length == 0) {
      result([self invalidArguments:@"copyFilesToLocal file destinations must be strings."]);
      return;
    }

    [self copyFileToLocal:@{
      @"deviceId" : deviceId,
      @"fileId" : fileId,
      @"destinationPath" : destinationPath,
    } result:^(id value) {
      if ([value isKindOfClass:[FlutterError class]]) {
        result(value);
        return;
      }
      [copiedPaths addObject:destinationPath];
      copyNext();
    }];
  };

  copyNext();
}

- (void)startBrowserIfNeeded {
  if (self.deviceBrowser != nil) {
    return;
  }

  self.deviceBrowser = [[ICDeviceBrowser alloc] init];
  self.deviceBrowser.delegate = self;
  self.deviceBrowser.browsedDeviceTypeMask =
      ICDeviceTypeMaskCamera | ICDeviceLocationTypeMaskLocal;
  [self.deviceBrowser start];
}

- (void)flushPendingDeviceResults {
  if (self.pendingDeviceResults.count == 0) {
    return;
  }

  NSArray *devices = [self encodedDevices];
  NSArray *results = [self.pendingDeviceResults copy];
  [self.pendingDeviceResults removeAllObjects];
  for (FlutterResult pendingResult in results) {
    pendingResult(devices);
  }
}

- (NSArray *)encodedDevices {
  NSMutableArray *encoded = [NSMutableArray array];
  for (NSString *deviceId in self.devicesById) {
    ICCameraDevice *device = self.devicesById[deviceId];
    [encoded addObject:@{
      @"id" : deviceId,
      @"name" : device.name ?: deviceId,
    }];
  }
  return encoded;
}

- (NSString *)idForDevice:(ICDevice *)device {
  NSString *candidate = device.persistentIDString;
  if (candidate.length == 0 && [device respondsToSelector:NSSelectorFromString(@"UUIDString")]) {
    candidate = [device valueForKey:@"UUIDString"];
  }
  if (candidate.length == 0 && [device respondsToSelector:NSSelectorFromString(@"uuidString")]) {
    candidate = [device valueForKey:@"uuidString"];
  }
  if (candidate.length == 0) {
    candidate = device.name;
  }
  if (candidate.length == 0) {
    candidate = [NSString stringWithFormat:@"%p", device];
  }
  return candidate;
}

- (NSString *)idForItem:(ICCameraItem *)item deviceId:(NSString *)deviceId prefix:(NSString *)prefix {
  NSString *name = item.name.length > 0 ? item.name : @"item";
  NSString *base = [NSString stringWithFormat:@"%@/%@", prefix.length > 0 ? prefix : kRootObjectId, name];
  NSString *itemId = [NSString stringWithFormat:@"%@::%@", deviceId, base];
  NSUInteger suffix = 2;
  while (self.itemsById[itemId] != nil && self.itemsById[itemId] != item) {
    itemId = [NSString stringWithFormat:@"%@::%@#%lu", deviceId, base, (unsigned long)suffix++];
  }
  return itemId;
}

- (void)indexItemTree:(ICCameraItem *)item deviceId:(NSString *)deviceId prefix:(NSString *)prefix {
  NSString *itemId = [self idForItem:item deviceId:deviceId prefix:prefix];
  self.itemsById[itemId] = item;

  if ([item isKindOfClass:[ICCameraFolder class]]) {
    NSArray<ICCameraItem *> *children = ((ICCameraFolder *)item).contents ?: @[];
    for (ICCameraItem *child in children) {
      [self indexItemTree:child deviceId:deviceId prefix:itemId];
    }
  }
}

- (NSDictionary *)encodedObject:(ICCameraItem *)item deviceId:(NSString *)deviceId {
  NSString *itemId = [self idForItem:item deviceId:deviceId prefix:[self parentPrefixForItem:item deviceId:deviceId]];
  self.itemsById[itemId] = item;
  return @{
    @"id" : itemId,
    @"name" : item.name ?: @"",
    @"isFolder" : @([item isKindOfClass:[ICCameraFolder class]]),
  };
}

- (NSDictionary *)encodedFile:(ICCameraFile *)file deviceId:(NSString *)deviceId prefix:(NSString *)prefix {
  NSString *itemId = [self idForItem:file deviceId:deviceId prefix:prefix];
  self.itemsById[itemId] = file;
  return @{
    @"id" : itemId,
    @"name" : file.name ?: @"",
    @"size" : @((long long)file.fileSize),
  };
}

- (NSString *)parentPrefixForItem:(ICCameraItem *)item deviceId:(NSString *)deviceId {
  ICCameraFolder *parent = item.parentFolder;
  if (parent == nil) {
    return kRootObjectId;
  }

  for (NSString *itemId in self.itemsById) {
    if (self.itemsById[itemId] == parent) {
      return itemId;
    }
  }
  return kRootObjectId;
}

- (NSArray<ICCameraItem *> *)childrenForObjectId:(NSString *)objectId
                                         device:(ICCameraDevice *)device
                                       deviceId:(NSString *)deviceId {
  if ([objectId isEqualToString:kRootObjectId]) {
    NSArray<ICCameraItem *> *contents = device.contents ?: @[];
    for (ICCameraItem *item in contents) {
      [self indexItemTree:item deviceId:deviceId prefix:kRootObjectId];
    }
    return contents;
  }

  ICCameraItem *item = self.itemsById[objectId];
  if ([item isKindOfClass:[ICCameraFolder class]]) {
    return ((ICCameraFolder *)item).contents ?: @[];
  }
  return nil;
}

- (void)appendMediaFilesFromItem:(ICCameraItem *)item
                        deviceId:(NSString *)deviceId
                          prefix:(NSString *)prefix
                      extensions:(NSSet<NSString *> *)extensions
                          output:(NSMutableArray *)output {
  NSString *itemId = [self idForItem:item deviceId:deviceId prefix:prefix];
  self.itemsById[itemId] = item;

  if ([item isKindOfClass:[ICCameraFolder class]]) {
    for (ICCameraItem *child in ((ICCameraFolder *)item).contents ?: @[]) {
      [self appendMediaFilesFromItem:child
                            deviceId:deviceId
                              prefix:itemId
                          extensions:extensions
                              output:output];
    }
    return;
  }

  if (![item isKindOfClass:[ICCameraFile class]]) {
    return;
  }

  NSString *extension = item.name.pathExtension.lowercaseString;
  if (extensions.count > 0 && ![extensions containsObject:extension]) {
    return;
  }

  [output addObject:[self encodedFile:(ICCameraFile *)item deviceId:deviceId prefix:prefix]];
}

- (void)openDevice:(ICCameraDevice *)device
          deviceId:(NSString *)deviceId
        completion:(void (^)(NSError *_Nullable))completion {
  [self startBrowserIfNeeded];
  device.delegate = self;

  if (device.hasOpenSession) {
    completion(nil);
    return;
  }

  NSMutableArray *pending = self.pendingSessionBlocks[deviceId];
  if (pending == nil) {
    pending = [NSMutableArray array];
    self.pendingSessionBlocks[deviceId] = pending;
  }
  [pending addObject:[completion copy]];

  if (pending.count == 1) {
    [device requestOpenSession];
  }
}

- (void)resolvePendingSessionsForDevice:(ICDevice *)device error:(NSError *)error {
  NSString *deviceId = [self idForDevice:device];
  NSArray *pending = [self.pendingSessionBlocks[deviceId] copy];
  [self.pendingSessionBlocks removeObjectForKey:deviceId];

  for (void (^completion)(NSError *) in pending) {
    completion(error);
  }
}

- (void)requestDownloadFile:(ICCameraFile *)file
                     device:(ICCameraDevice *)device
            destinationPath:(NSString *)destinationPath
                     result:(FlutterResult)result {
  NSURL *destinationURL = [NSURL fileURLWithPath:destinationPath];
  NSURL *directoryURL = [destinationURL URLByDeletingLastPathComponent];
  NSString *fileName = destinationURL.lastPathComponent;
  if (directoryURL == nil || fileName.length == 0) {
    result([self invalidArguments:@"destinationPath must include a file name."]);
    return;
  }

  NSError *directoryError = nil;
  [[NSFileManager defaultManager] createDirectoryAtURL:directoryURL
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:&directoryError];
  if (directoryError != nil) {
    result([self flutterError:@"macos_file_error"
                      message:directoryError.localizedDescription
                      details:@(directoryError.code)]);
    return;
  }

  NSString *downloadKey = [NSString stringWithFormat:@"%p", file];
  self.pendingDownloads[downloadKey] = [result copy];

  NSDictionary *options = @{
    ICDownloadsDirectoryURL : directoryURL,
    ICSaveAsFilename : fileName,
    ICOverwrite : @YES,
  };

  [device requestDownloadFile:file
                      options:options
             downloadDelegate:self
          didDownloadSelector:@selector(didDownloadFile:error:options:contextInfo:)
                  contextInfo:nil];
}

- (NSString *)stringValue:(id)value {
  return [value isKindOfClass:[NSString class]] ? (NSString *)value : @"";
}

- (NSSet<NSString *> *)normalizedExtensions:(NSArray *)extensions {
  NSMutableSet<NSString *> *normalized = [NSMutableSet set];
  for (id value in extensions) {
    if (![value isKindOfClass:[NSString class]]) {
      continue;
    }
    NSString *extension = [((NSString *)value).lowercaseString stringByTrimmingCharactersInSet:
        [NSCharacterSet characterSetWithCharactersInString:@"."]];
    if (extension.length > 0) {
      [normalized addObject:extension];
    }
  }
  return normalized;
}

- (FlutterError *)invalidArguments:(NSString *)message {
  return [self flutterError:@"invalid_arguments" message:message details:nil];
}

- (FlutterError *)deviceNotFound:(NSString *)deviceId {
  return [self flutterError:@"device_not_found"
                    message:[NSString stringWithFormat:@"MTP/ImageCapture device not found: %@", deviceId]
                    details:nil];
}

- (FlutterError *)objectNotFound:(NSString *)objectId {
  return [self flutterError:@"object_not_found"
                    message:[NSString stringWithFormat:@"MTP/ImageCapture object not found: %@", objectId]
                    details:nil];
}

- (FlutterError *)flutterError:(NSString *)code message:(NSString *)message details:(id)details {
  return [FlutterError errorWithCode:code message:message details:details];
}

#pragma mark - ICDeviceBrowserDelegate

- (void)deviceBrowser:(ICDeviceBrowser *)browser didAddDevice:(ICDevice *)device moreComing:(BOOL)moreComing {
  if (![device isKindOfClass:[ICCameraDevice class]]) {
    return;
  }

  NSString *deviceId = [self idForDevice:device];
  ICCameraDevice *cameraDevice = (ICCameraDevice *)device;
  cameraDevice.delegate = self;
  self.devicesById[deviceId] = cameraDevice;

  if (!moreComing) {
    self.didEnumerateInitialDevices = YES;
    [self flushPendingDeviceResults];
  }
}

- (void)deviceBrowser:(ICDeviceBrowser *)browser didRemoveDevice:(ICDevice *)device moreGoing:(BOOL)moreGoing {
  NSString *deviceId = [self idForDevice:device];
  [self.devicesById removeObjectForKey:deviceId];
}

- (void)deviceBrowserDidEnumerateLocalDevices:(ICDeviceBrowser *)browser {
  self.didEnumerateInitialDevices = YES;
  [self flushPendingDeviceResults];
}

#pragma mark - ICDeviceDelegate / ICCameraDeviceDelegate

- (void)device:(ICDevice *)device didOpenSessionWithError:(NSError *)error {
  if (error != nil) {
    [self resolvePendingSessionsForDevice:device error:error];
    return;
  }

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
                   [self resolvePendingSessionsForDevice:device error:nil];
                 });
}

- (void)deviceDidBecomeReadyWithCompleteContentCatalog:(ICCameraDevice *)device {
  [self resolvePendingSessionsForDevice:device error:nil];
}

- (void)cameraDevice:(ICCameraDevice *)camera didAddItem:(ICCameraItem *)item {
  NSString *deviceId = [self idForDevice:camera];
  [self indexItemTree:item deviceId:deviceId prefix:kRootObjectId];
}

- (void)cameraDevice:(ICCameraDevice *)camera didRemoveItem:(ICCameraItem *)item {
}

- (void)cameraDevice:(ICCameraDevice *)camera didReceiveThumbnailForItem:(ICCameraItem *)item {
}

- (void)cameraDevice:(ICCameraDevice *)camera didReceiveMetadataForItem:(ICCameraItem *)item {
}

- (void)cameraDevice:(ICCameraDevice *)camera didRenameItems:(NSArray<ICCameraItem *> *)items {
}

- (void)cameraDeviceDidChangeCapability:(ICCameraDevice *)camera {
}

#pragma mark - ICCameraDeviceDownloadDelegate

- (void)didDownloadFile:(ICCameraFile *)file
                  error:(NSError *)error
                options:(NSDictionary *)options
            contextInfo:(void *)contextInfo {
  NSString *downloadKey = [NSString stringWithFormat:@"%p", file];
  FlutterResult result = self.pendingDownloads[downloadKey];
  [self.pendingDownloads removeObjectForKey:downloadKey];
  if (result == nil) {
    return;
  }

  if (error != nil) {
    result([self flutterError:@"macos_image_capture_error"
                      message:error.localizedDescription
                      details:@(error.code)]);
    return;
  }

  NSURL *directoryURL = options[ICDownloadsDirectoryURL];
  NSString *savedFilename = options[ICSavedFilename] ?: options[ICSaveAsFilename] ?: file.name;
  NSString *path = directoryURL != nil && savedFilename.length > 0
      ? [directoryURL.path stringByAppendingPathComponent:savedFilename]
      : @"";
  result(path);
}

- (void)didReceiveDownloadProgressForFile:(ICCameraFile *)file
                          downloadedBytes:(off_t)downloadedBytes
                                 maxBytes:(off_t)maxBytes {
}

@end

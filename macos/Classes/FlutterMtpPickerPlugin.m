#import "FlutterMtpPickerPlugin.h"

#include <libmtp.h>
#include <stdlib.h>

static NSString *const kChannelName = @"flutter_mtp_picker";
static NSString *const kRootObjectId = @"ROOT";
static uint32_t const kMtpRootParentId = 0xffffffff;

static void CompleteOnMain(FlutterResult result, id value) {
  dispatch_async(dispatch_get_main_queue(), ^{
    result(value);
  });
}

@interface FlutterMtpPickerPlugin ()
@property(nonatomic, strong) dispatch_queue_t mtpQueue;
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
    LIBMTP_Init();
    _mtpQueue = dispatch_queue_create("flutter_mtp_picker.libmtp", DISPATCH_QUEUE_SERIAL);
  }
  return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([@"getDevices" isEqualToString:call.method]) {
    [self getDevices:result];
    return;
  }

  NSDictionary *arguments = [self dictionaryArguments:call.arguments result:result method:call.method];
  if (arguments == nil) {
    return;
  }

  if ([@"listChildren" isEqualToString:call.method]) {
    [self listChildren:arguments result:result];
  } else if ([@"listMediaFiles" isEqualToString:call.method]) {
    [self listMediaFiles:arguments result:result];
  } else if ([@"copyFileToLocal" isEqualToString:call.method]) {
    [self copyFileToLocal:arguments result:result];
  } else if ([@"copyFilesToLocal" isEqualToString:call.method]) {
    [self copyFilesToLocal:arguments result:result];
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (NSDictionary *)dictionaryArguments:(id)arguments
                               result:(FlutterResult)result
                               method:(NSString *)method {
  if (![arguments isKindOfClass:[NSDictionary class]]) {
    result([self invalidArguments:[NSString stringWithFormat:@"%@ expects an argument map.", method]]);
    return nil;
  }
  return (NSDictionary *)arguments;
}

- (void)getDevices:(FlutterResult)result {
  dispatch_async(self.mtpQueue, ^{
    LIBMTP_raw_device_t *rawDevices = NULL;
    int rawDeviceCount = 0;
    LIBMTP_error_number_t error = LIBMTP_Detect_Raw_Devices(&rawDevices, &rawDeviceCount);
    if (error == LIBMTP_ERROR_NO_DEVICE_ATTACHED) {
      CompleteOnMain(result, @[]);
      return;
    }
    if (error != LIBMTP_ERROR_NONE) {
      CompleteOnMain(result, [self libmtpDetectError:error]);
      return;
    }

    NSMutableArray *devices = [NSMutableArray array];
    for (int index = 0; index < rawDeviceCount; index++) {
      LIBMTP_raw_device_t rawDevice = rawDevices[index];
      NSString *deviceId = [self idForRawDevice:&rawDevice index:index];
      NSString *vendor = [self stringFromCString:rawDevice.device_entry.vendor fallback:@""];
      NSString *product = [self stringFromCString:rawDevice.device_entry.product fallback:@""];
      NSString *name = [self joinedDeviceNameWithVendor:vendor product:product fallback:deviceId];
      [devices addObject:@{@"id" : deviceId, @"name" : name}];
    }

    if (rawDevices != NULL) {
      free(rawDevices);
    }
    CompleteOnMain(result, devices);
  });
}

- (void)listChildren:(NSDictionary *)arguments result:(FlutterResult)result {
  NSString *deviceId = [self stringValue:arguments[@"deviceId"]];
  NSString *objectId = [self stringValue:arguments[@"objectId"]];
  if (deviceId.length == 0 || objectId.length == 0) {
    result([self invalidArguments:@"listChildren requires deviceId and objectId."]);
    return;
  }

  dispatch_async(self.mtpQueue, ^{
    LIBMTP_mtpdevice_t *device = [self openDeviceById:deviceId errorResult:result];
    if (device == NULL) {
      return;
    }

    id response = nil;
    if ([objectId isEqualToString:kRootObjectId]) {
      response = [self encodedStoragesForDevice:device];
    } else {
      uint32_t storageId = 0;
      uint32_t parentId = 0;
      if (![self parseFolderObjectId:objectId storageId:&storageId parentId:&parentId]) {
        response = [self objectNotFound:objectId];
      } else {
        response = [self encodedChildrenForDevice:device storageId:storageId parentId:parentId];
      }
    }

    LIBMTP_Release_Device(device);
    CompleteOnMain(result, response);
  });
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

  NSSet<NSString *> *normalizedExtensions = [self normalizedExtensions:extensions];
  dispatch_async(self.mtpQueue, ^{
    LIBMTP_mtpdevice_t *device = [self openDeviceById:deviceId errorResult:result];
    if (device == NULL) {
      return;
    }

    NSMutableArray *files = [NSMutableArray array];
    id error = nil;
    if ([folderId isEqualToString:kRootObjectId]) {
      error = [self appendMediaFilesFromAllStoragesForDevice:device
                                                  extensions:normalizedExtensions
                                                      output:files];
    } else {
      uint32_t storageId = 0;
      uint32_t parentId = 0;
      if (![self parseFolderObjectId:folderId storageId:&storageId parentId:&parentId]) {
        error = [self objectNotFound:folderId];
      } else {
        error = [self appendMediaFilesForDevice:device
                                      storageId:storageId
                                       parentId:parentId
                                     extensions:normalizedExtensions
                                         output:files];
      }
    }

    LIBMTP_Release_Device(device);
    CompleteOnMain(result, error ?: files);
  });
}

- (void)copyFileToLocal:(NSDictionary *)arguments result:(FlutterResult)result {
  NSString *deviceId = [self stringValue:arguments[@"deviceId"]];
  NSString *fileId = [self stringValue:arguments[@"fileId"]];
  NSString *destinationPath = [self stringValue:arguments[@"destinationPath"]];
  if (deviceId.length == 0 || fileId.length == 0 || destinationPath.length == 0) {
    result([self invalidArguments:@"copyFileToLocal requires deviceId, fileId, and destinationPath."]);
    return;
  }

  uint32_t storageId = 0;
  uint32_t itemId = 0;
  if (![self parseObjectId:fileId storageId:&storageId itemId:&itemId]) {
    result([self objectNotFound:fileId]);
    return;
  }

  dispatch_async(self.mtpQueue, ^{
    LIBMTP_mtpdevice_t *device = [self openDeviceById:deviceId errorResult:result];
    if (device == NULL) {
      return;
    }

    NSString *directory = [destinationPath stringByDeletingLastPathComponent];
    NSError *directoryError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&directoryError];
    if (directoryError != nil) {
      LIBMTP_Release_Device(device);
      CompleteOnMain(result, [self flutterError:@"macos_file_error"
                                        message:directoryError.localizedDescription
                                        details:@(directoryError.code)]);
      return;
    }

    int copyResult = LIBMTP_Get_File_To_File(device, itemId, destinationPath.fileSystemRepresentation, NULL, NULL);
    if (copyResult != 0) {
      FlutterError *error = [self libmtpOperationError:device operation:@"copyFileToLocal"];
      LIBMTP_Release_Device(device);
      CompleteOnMain(result, error);
      return;
    }

    LIBMTP_Release_Device(device);
    CompleteOnMain(result, destinationPath);
  });
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

  dispatch_async(self.mtpQueue, ^{
    LIBMTP_mtpdevice_t *device = [self openDeviceById:deviceId errorResult:result];
    if (device == NULL) {
      return;
    }

    NSMutableArray *copiedPaths = [NSMutableArray array];
    for (id key in files) {
      NSString *fileId = [self stringValue:key];
      NSString *destinationPath = [self stringValue:files[key]];
      uint32_t storageId = 0;
      uint32_t itemId = 0;
      if (fileId.length == 0 || destinationPath.length == 0 ||
          ![self parseObjectId:fileId storageId:&storageId itemId:&itemId]) {
        LIBMTP_Release_Device(device);
        CompleteOnMain(result, [self invalidArguments:@"copyFilesToLocal expects a string map of file IDs to destination paths."]);
        return;
      }

      NSString *directory = [destinationPath stringByDeletingLastPathComponent];
      NSError *directoryError = nil;
      [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:&directoryError];
      if (directoryError != nil) {
        LIBMTP_Release_Device(device);
        CompleteOnMain(result, [self flutterError:@"macos_file_error"
                                          message:directoryError.localizedDescription
                                          details:@(directoryError.code)]);
        return;
      }

      int copyResult = LIBMTP_Get_File_To_File(device, itemId, destinationPath.fileSystemRepresentation, NULL, NULL);
      if (copyResult != 0) {
        FlutterError *error = [self libmtpOperationError:device operation:@"copyFilesToLocal"];
        LIBMTP_Release_Device(device);
        CompleteOnMain(result, error);
        return;
      }
      [copiedPaths addObject:destinationPath];
    }

    LIBMTP_Release_Device(device);
    CompleteOnMain(result, copiedPaths);
  });
}

- (LIBMTP_mtpdevice_t *)openDeviceById:(NSString *)deviceId errorResult:(FlutterResult)result {
  LIBMTP_raw_device_t *rawDevices = NULL;
  int rawDeviceCount = 0;
  LIBMTP_error_number_t detectError = LIBMTP_Detect_Raw_Devices(&rawDevices, &rawDeviceCount);
  if (detectError == LIBMTP_ERROR_NO_DEVICE_ATTACHED) {
    CompleteOnMain(result, [self deviceNotFound:deviceId]);
    return NULL;
  }
  if (detectError != LIBMTP_ERROR_NONE) {
    CompleteOnMain(result, [self libmtpDetectError:detectError]);
    return NULL;
  }

  LIBMTP_mtpdevice_t *device = NULL;
  for (int index = 0; index < rawDeviceCount; index++) {
    LIBMTP_raw_device_t *rawDevice = &rawDevices[index];
    NSString *candidateId = [self idForRawDevice:rawDevice index:index];
    if ([candidateId isEqualToString:deviceId]) {
      device = LIBMTP_Open_Raw_Device_Uncached(rawDevice);
      break;
    }
  }

  if (rawDevices != NULL) {
    free(rawDevices);
  }

  if (device == NULL) {
    CompleteOnMain(result, [self deviceNotFound:deviceId]);
  }
  return device;
}

- (NSArray *)encodedStoragesForDevice:(LIBMTP_mtpdevice_t *)device {
  int storageResult = LIBMTP_Get_Storage(device, LIBMTP_STORAGE_SORTBY_NOTSORTED);
  if (storageResult != 0) {
    return @[];
  }

  NSMutableArray *storages = [NSMutableArray array];
  for (LIBMTP_devicestorage_t *storage = device->storage; storage != NULL; storage = storage->next) {
    NSString *storageName = [self stringFromCString:storage->StorageDescription fallback:@"Storage"];
    [storages addObject:@{
      @"id" : [self storageObjectId:storage->id],
      @"name" : storageName,
      @"isFolder" : @YES,
    }];
  }
  return storages;
}

- (NSArray *)encodedChildrenForDevice:(LIBMTP_mtpdevice_t *)device
                            storageId:(uint32_t)storageId
                             parentId:(uint32_t)parentId {
  LIBMTP_file_t *children = LIBMTP_Get_Files_And_Folders(device, storageId, parentId);
  NSMutableArray *encoded = [NSMutableArray array];

  for (LIBMTP_file_t *file = children; file != NULL; file = file->next) {
    [encoded addObject:[self encodedFile:file storageId:storageId]];
  }

  if (children != NULL) {
    LIBMTP_destroy_file_t(children);
  }
  return encoded;
}

- (id)appendMediaFilesFromAllStoragesForDevice:(LIBMTP_mtpdevice_t *)device
                                    extensions:(NSSet<NSString *> *)extensions
                                        output:(NSMutableArray *)output {
  int storageResult = LIBMTP_Get_Storage(device, LIBMTP_STORAGE_SORTBY_NOTSORTED);
  if (storageResult != 0) {
    return [self libmtpOperationError:device operation:@"listMediaFiles"];
  }

  for (LIBMTP_devicestorage_t *storage = device->storage; storage != NULL; storage = storage->next) {
    id error = [self appendMediaFilesForDevice:device
                                     storageId:storage->id
                                      parentId:kMtpRootParentId
                                    extensions:extensions
                                        output:output];
    if (error != nil) {
      return error;
    }
  }
  return nil;
}

- (id)appendMediaFilesForDevice:(LIBMTP_mtpdevice_t *)device
                      storageId:(uint32_t)storageId
                       parentId:(uint32_t)parentId
                     extensions:(NSSet<NSString *> *)extensions
                         output:(NSMutableArray *)output {
  LIBMTP_file_t *children = LIBMTP_Get_Files_And_Folders(device, storageId, parentId);
  if (children == NULL) {
    return nil;
  }

  for (LIBMTP_file_t *file = children; file != NULL; file = file->next) {
    if (file->filetype == LIBMTP_FILETYPE_FOLDER) {
      id error = [self appendMediaFilesForDevice:device
                                       storageId:storageId
                                        parentId:file->item_id
                                      extensions:extensions
                                          output:output];
      if (error != nil) {
        LIBMTP_destroy_file_t(children);
        return error;
      }
    } else if ([self file:file matchesExtensions:extensions]) {
      [output addObject:[self encodedMediaFile:file storageId:storageId]];
    }
  }

  LIBMTP_destroy_file_t(children);
  return nil;
}

- (NSDictionary *)encodedFile:(LIBMTP_file_t *)file storageId:(uint32_t)storageId {
  BOOL isFolder = file->filetype == LIBMTP_FILETYPE_FOLDER;
  return @{
    @"id" : [self objectIdForStorageId:storageId itemId:file->item_id],
    @"name" : [self stringFromCString:file->filename fallback:@""],
    @"isFolder" : @(isFolder),
  };
}

- (NSDictionary *)encodedMediaFile:(LIBMTP_file_t *)file storageId:(uint32_t)storageId {
  return @{
    @"id" : [self objectIdForStorageId:storageId itemId:file->item_id],
    @"name" : [self stringFromCString:file->filename fallback:@""],
    @"size" : @((long long)file->filesize),
  };
}

- (BOOL)file:(LIBMTP_file_t *)file matchesExtensions:(NSSet<NSString *> *)extensions {
  if (extensions.count == 0) {
    return YES;
  }
  NSString *filename = [self stringFromCString:file->filename fallback:@""];
  NSString *extension = filename.pathExtension.lowercaseString;
  return [extensions containsObject:extension];
}

- (NSString *)idForRawDevice:(LIBMTP_raw_device_t *)rawDevice index:(int)index {
  return [NSString stringWithFormat:@"raw:%u:%u:%d",
                                    rawDevice->bus_location,
                                    rawDevice->devnum,
                                    index];
}

- (NSString *)storageObjectId:(uint32_t)storageId {
  return [NSString stringWithFormat:@"storage:%u", storageId];
}

- (NSString *)objectIdForStorageId:(uint32_t)storageId itemId:(uint32_t)itemId {
  return [NSString stringWithFormat:@"object:%u:%u", storageId, itemId];
}

- (BOOL)parseFolderObjectId:(NSString *)objectId storageId:(uint32_t *)storageId parentId:(uint32_t *)parentId {
  if ([objectId hasPrefix:@"storage:"]) {
    if (![self parseUInt32:[objectId substringFromIndex:@"storage:".length] value:storageId]) {
      return NO;
    }
    *parentId = kMtpRootParentId;
    return *storageId != 0;
  }

  uint32_t itemId = 0;
  if ([self parseObjectId:objectId storageId:storageId itemId:&itemId]) {
    *parentId = itemId;
    return YES;
  }

  return NO;
}

- (BOOL)parseObjectId:(NSString *)objectId storageId:(uint32_t *)storageId itemId:(uint32_t *)itemId {
  NSArray<NSString *> *parts = [objectId componentsSeparatedByString:@":"];
  if (parts.count != 3 || ![parts[0] isEqualToString:@"object"]) {
    return NO;
  }

  if (![self parseUInt32:parts[1] value:storageId] || ![self parseUInt32:parts[2] value:itemId]) {
    return NO;
  }
  return *storageId != 0 && *itemId != 0;
}

- (BOOL)parseUInt32:(NSString *)string value:(uint32_t *)value {
  const char *rawValue = string.UTF8String;
  if (rawValue == NULL || rawValue[0] == '\0') {
    return NO;
  }

  char *end = NULL;
  unsigned long long parsedValue = strtoull(rawValue, &end, 10);
  if (end == rawValue || *end != '\0' || parsedValue > UINT32_MAX) {
    return NO;
  }

  *value = (uint32_t)parsedValue;
  return YES;
}

- (NSString *)stringValue:(id)value {
  return [value isKindOfClass:[NSString class]] ? (NSString *)value : @"";
}

- (NSString *)stringFromCString:(const char *)value fallback:(NSString *)fallback {
  if (value == NULL || value[0] == '\0') {
    return fallback;
  }
  return [NSString stringWithUTF8String:value] ?: fallback;
}

- (NSString *)joinedDeviceNameWithVendor:(NSString *)vendor
                                 product:(NSString *)product
                                fallback:(NSString *)fallback {
  if (vendor.length > 0 && product.length > 0) {
    return [NSString stringWithFormat:@"%@ %@", vendor, product];
  }
  if (product.length > 0) {
    return product;
  }
  if (vendor.length > 0) {
    return vendor;
  }
  return fallback;
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

- (FlutterError *)libmtpDetectError:(LIBMTP_error_number_t)error {
  return [self flutterError:@"macos_libmtp_error"
                    message:[NSString stringWithFormat:@"libmtp device detection failed: %d", error]
                    details:@(error)];
}

- (FlutterError *)libmtpOperationError:(LIBMTP_mtpdevice_t *)device operation:(NSString *)operation {
  NSString *message = [NSString stringWithFormat:@"%@ failed.", operation];
  LIBMTP_error_t *error = device != NULL ? device->errorstack : NULL;
  if (error != NULL && error->error_text != NULL) {
    message = [NSString stringWithFormat:@"%@ failed: %@", operation, [self stringFromCString:error->error_text fallback:@"libmtp error"]];
  }
  if (device != NULL) {
    LIBMTP_Clear_Errorstack(device);
  }
  return [self flutterError:@"macos_libmtp_error" message:message details:nil];
}

- (FlutterError *)invalidArguments:(NSString *)message {
  return [self flutterError:@"invalid_arguments" message:message details:nil];
}

- (FlutterError *)deviceNotFound:(NSString *)deviceId {
  return [self flutterError:@"device_not_found"
                    message:[NSString stringWithFormat:@"MTP device not found: %@", deviceId]
                    details:nil];
}

- (FlutterError *)objectNotFound:(NSString *)objectId {
  return [self flutterError:@"object_not_found"
                    message:[NSString stringWithFormat:@"MTP object not found: %@", objectId]
                    details:nil];
}

- (FlutterError *)flutterError:(NSString *)code message:(NSString *)message details:(id)details {
  return [FlutterError errorWithCode:code message:message details:details];
}

@end

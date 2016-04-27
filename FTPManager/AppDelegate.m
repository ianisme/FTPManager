//
//  AppDelegate.m
//  FTPManager
//
//  Created by Nico Kreipke on 08.06.12.
//  Copyright (c) 2012 nkreipke. All rights reserved.
//

#import "AppDelegate.h"

@implementation AppDelegate
{
    NSUInteger _diri;
    NSDictionary *_dicFilesDirs;
    NSString *_directoryFieldString;
    NSString *_fileURLString;
}
@synthesize createDirectoryField = _createDirectoryField;
@synthesize directoryField = _directoryField;
@synthesize directoryPanel = _directoryPanel;
@synthesize downloadFileField = _downloadFileField;
@synthesize downloadFilePanel = _downloadFilePanel;
@synthesize actionProgressField = _actionProgressField;
@synthesize actionProgressBar = _actionProgressBar;
@synthesize actionPanel = _actionPanel;
@synthesize fileListOutputField = _fileListOutputField;
@synthesize fileListOutputPanel = _fileListOutputPanel;
@synthesize loginPasswordField = _loginPasswordField;
@synthesize loginUserField = _loginUserField;
@synthesize serverURLField = _serverURLField;

@synthesize window = _window;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
}

- (void)didEndSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    [sheet orderOut:self];
}

#pragma mark - Progress

- (void)reloadProgress {
    if (ftpManager) {
        NSDictionary* progress = [ftpManager progress];
        if (progress) {
            NSNumber* prog = [progress objectForKey:(id)kFMProcessInfoProgress];
            [self.actionProgressBar setDoubleValue:[prog doubleValue]];
            NSNumber* bytesProcessed = [progress objectForKey:(id)kFMProcessInfoFileSizeProcessed];
            NSNumber* fileSize = [progress objectForKey:(id)kFMProcessInfoFileSize];
            [self.actionProgressField setStringValue:[NSString stringWithFormat:@"%i bytes of %i bytes",[bytesProcessed intValue],[fileSize intValue]]];
        }
    }
}

#pragma mark - Processing Files List

-(NSString*)processDict:(NSDictionary*)dict {
    NSString* name = [dict objectForKey:(id)kCFFTPResourceName];
    NSNumber* size = [dict objectForKey:(id)kCFFTPResourceSize];
    NSDate* mod = [dict objectForKey:(id)kCFFTPResourceModDate];
    NSNumber* type = [dict objectForKey:(id)kCFFTPResourceType];
    NSNumber* mode = [dict objectForKey:(id)kCFFTPResourceMode];
    NSString* isFolder = ([type intValue] == 4) ? @"(folder) " : @"";
    return [NSString stringWithFormat:@"%@ %@--- size %i bytes - mode:%i - modDate: %@\n",name,isFolder,[size intValue],[mode intValue],[mod description]];
}

-(void)processSData:(NSArray*)data {
    NSString* str = @"";
    for (NSDictionary* d in data) {
        str = [str stringByAppendingString:[self processDict:d]];
    }
    [self.fileListOutputField setString:str];
    [NSApp beginSheet:self.fileListOutputPanel modalForWindow:self.window modalDelegate:self didEndSelector:@selector(didEndSheet:returnCode:contextInfo:) contextInfo:nil];
}

#pragma mark - FTPManager interaction

-(void)endRunAction:(NSArray*)optionalServerData {
    [NSApp endSheet:self.actionPanel];
    if (progressTimer) {
        [progressTimer invalidate];
        progressTimer = nil;
    }
    [self.actionProgressBar stopAnimation:self];
    if (!aborted) {
        if (optionalServerData) {
            [self processSData:optionalServerData];
        } else {
            if (success) {
                NSBeginInformationalAlertSheet(@"Success", @"Close", nil, nil, self.window, self, nil, nil, nil, @"Action completed successfully.");
            } else {
                NSBeginAlertSheet(@"Error", @"Close", nil, nil, self.window, self, nil, nil, nil, @"An error occurred.");
            }
        }
    }
}

- (NSDictionary *)allFilesAtPath:(NSString *)dirString
{
    NSMutableDictionary *resultDic = [@{} mutableCopy];
    NSMutableArray *resultFiles = [@[] mutableCopy];
    NSMutableArray *resultDirs = [@[] mutableCopy];
    NSArray *contentOfFolder = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dirString error:NULL];
    for (NSString *aPath in contentOfFolder) {
        NSString * fullPath = [dirString stringByAppendingPathComponent:aPath];
        BOOL isDir;
        if ([[NSFileManager defaultManager] fileExistsAtPath:fullPath isDirectory:&isDir] && !isDir) {
            
            [resultFiles addObject:[NSString stringWithFormat:@"file://%@",fullPath]];
            
        } else {
            if (![[aPath substringToIndex:1] containsString:@"."]) {
                NSMutableDictionary *dic = [@{}mutableCopy];
                dic[aPath] = [self allFilesAtPath:fullPath];
                [resultDirs addObject:dic];
            }
        }
    }
    resultDic[@"dir"] = resultDirs;
    resultDic[@"file"] = resultFiles;
    return resultDic;
}

- (NSMutableArray *)creatDirsArray:(NSDictionary *)dic dirAddress:(NSString *)dirAddress
{
    NSMutableArray *uploadCreatDirArray = [@[] mutableCopy];
    NSArray *dirArray = dic.allKeys;
    for (NSString *dirName in dirArray) {
        NSMutableDictionary *dic1 = [@{}mutableCopy];
        dic1[@"directoryField"] = dirAddress;
        dic1[@"dirName"] = dirName;
        [uploadCreatDirArray addObject:dic1];
        
        NSArray *dirArray2 = dic[dirName][@"dir"];
        for (NSDictionary *dic2 in dirArray2) {
            [uploadCreatDirArray addObjectsFromArray:[self creatDirsArray:dic2 dirAddress:[dirAddress stringByAppendingString:[NSString stringWithFormat:@"/%@",dirName]]]];
        }
        
    }
    
    return uploadCreatDirArray;
    
}

- (NSMutableArray *)creatFilesArray:(NSDictionary *)dic dirAddress:(NSString *)dirAddress
{
    NSMutableArray *uploadCreatFileArray = [@[] mutableCopy];
    NSArray *dirArray = dic.allKeys;
    for (NSString *dirName in dirArray) {

        NSArray *filesArray = dic[dirName][@"file"];
        NSString *dirAddress1 = [dirAddress stringByAppendingString:[NSString stringWithFormat:@"/%@",dirName]];
        for (NSString *fileName in filesArray) {
            NSMutableDictionary *dic1 = [@{} mutableCopy];
            dic1[@"directoryField"] = dirAddress1;
            dic1[@"fileName"] = fileName;
            [uploadCreatFileArray addObject:dic1];
        }
        
        NSArray *dirsArray = dic[dirName][@"dir"];
        for (NSDictionary *dic2 in dirsArray) {
            [uploadCreatFileArray addObjectsFromArray:[self creatFilesArray:dic2 dirAddress:[dirAddress stringByAppendingString:[NSString stringWithFormat:@"/%@",dirName]]]];
        }
        
    }
    
    return uploadCreatFileArray;
}


- (void)uploadCreatDtr:(NSTimer *)timer
{
    NSArray *array = timer.userInfo;
    
    if (action == nothing && _diri == array.count) {
        [timer invalidate];
        _diri = 0;
        action = nothing;
        NSArray *array = [self creatFilesArray:_dicFilesDirs dirAddress:_directoryFieldString];
        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(uploadCreatFile:) userInfo:array repeats:TRUE];
        
    } else if (action == nothing && _diri != array.count) {
        NSDictionary *dic = array[_diri];
        self.createDirectoryField.stringValue = dic[@"dirName"];
        self.directoryField.stringValue = dic[@"directoryField"];
        _diri++;
        action = newfolder;
        [self performSelectorInBackground:@selector(_runAction) withObject:nil];
    
    }
}

- (void)uploadCreatFile:(NSTimer *)timer
{
    NSArray *array = timer.userInfo;
    double abc = floor(_diri/(array.count*1.0)*100) / 100;
    [self.actionProgressBar setDoubleValue:abc];
    
    [self.actionProgressField setStringValue:[NSString stringWithFormat:@"%%%zd",[@(_diri*100/array.count*1.0) integerValue]]];
    
//    progressTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(reloadProgress) userInfo:nil repeats:YES];
    if (action == nothing && _diri == array.count) {
        [timer invalidate];
        _diri = 0;
        [self performSelectorOnMainThread:@selector(endRunAction:) withObject:nil waitUntilDone:NO];
    } else if (action == nothing && _diri != array.count) {
        NSDictionary *dic = array[_diri];
        fileURL = [NSURL URLWithString:dic[@"fileName"]];
        self.directoryField.stringValue = dic[@"directoryField"];
        _diri++;
        action = upload;
        [self performSelectorInBackground:@selector(_runAction) withObject:nil];
    }
}

- (void)_runAction {
    ftpManager = [[FTPManager alloc] init];
    success = NO;
    NSArray* serverData = nil;
    FMServer* srv = [FMServer serverWithDestination:[self.serverURLField.stringValue stringByAppendingPathComponent:self.directoryField.stringValue] username:self.loginUserField.stringValue password:self.loginPasswordField.stringValue];
    srv.port = self.portField.intValue;
    
    switch (action) {
        case upload:
            success = [ftpManager uploadFile:fileURL toServer:srv];
            break;
        case download:
            success = [ftpManager downloadFile:self.downloadFileField.stringValue toDirectory:[NSURL fileURLWithPath:NSHomeDirectory()] fromServer:srv];
            break;
        case newfolder:
            success = [ftpManager createNewFolder:self.createDirectoryField.stringValue atServer:srv];
            break;
        case list:
            serverData = [ftpManager contentsOfServer:srv];
            break;
        case del:
            success = [ftpManager deleteFileNamed:self.deleteFileField.stringValue fromServer:srv];
            break;
        case chmod:
            success = [ftpManager chmodFileNamed:self.chmodFileField.stringValue to:self.chmodModeField.intValue atServer:srv];
            break;
        default:
            break;
    }
    if (![[_fileURLString substringFromIndex:([_fileURLString length]-1)] isEqualToString:@"/"]) {
        [self performSelectorOnMainThread:@selector(endRunAction:) withObject:serverData waitUntilDone:NO];
    }
    action = nothing;
}

-(void)runAction {
    aborted = NO;
    [NSApp beginSheet:self.actionPanel modalForWindow:self.window modalDelegate:self didEndSelector:@selector(didEndSheet:returnCode:contextInfo:) contextInfo:nil];
    if (action != nothing) {
        
        if ([[fileURL.absoluteString substringFromIndex:([fileURL.absoluteString length]-1)] isEqualToString:@"/"]) {
            // 是目录
            NSString *path = [[fileURL.absoluteString componentsSeparatedByString:@"file://"] lastObject];
            NSLog(@"%@",[self allFilesAtPath:path]);
            
            NSArray *array = [fileURL.absoluteString componentsSeparatedByString:@"/"];
            NSMutableDictionary *fileDic = [@{} mutableCopy];
            fileDic[array[array.count-1-1]] = [self allFilesAtPath:path];
            NSLog(@"%@",[self creatDirsArray:fileDic dirAddress:self.directoryField.stringValue]);
            _dicFilesDirs = fileDic;
            _directoryFieldString = [self.directoryField.stringValue copy];
            _fileURLString = [fileURL.absoluteString copy];
            NSArray *DirsArray = [self creatDirsArray:_dicFilesDirs dirAddress:self.directoryField.stringValue];
            
            action = nothing;
            _diri = 0;
            
            [self.actionProgressField setStringValue:@""];
            [self.actionProgressBar setMaxValue:1.0];
            [self.actionProgressBar setIndeterminate:NO];
            [self.actionProgressBar setDoubleValue:0.0];
            
            [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(uploadCreatDtr:) userInfo:DirsArray repeats:TRUE];
            
            
        } else {
            [self performSelectorInBackground:@selector(_runAction) withObject:nil];
            [self.actionProgressField setStringValue:@""];
            [self.actionProgressBar setMaxValue:1.0];
            if (action == download || action == upload) {
                [self.actionProgressBar setIndeterminate:NO];
                [self.actionProgressBar setDoubleValue:0.0];
                progressTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(reloadProgress) userInfo:nil repeats:YES];
            } else {
                [self.actionProgressBar startAnimation:self];
                [self.actionProgressBar setIndeterminate:YES];
            }
        }
    }
}

#pragma mark - View things

- (IBAction)pushUploadAFile:(id)sender {
    NSOpenPanel* openPanel = [NSOpenPanel openPanel];
    [openPanel setCanChooseFiles:YES];
    [openPanel setCanChooseDirectories:YES];
    [openPanel setAllowsMultipleSelection:NO];
    [openPanel setResolvesAliases:YES];
    [openPanel setPrompt:@"Upload"];
    [openPanel setDirectoryURL:[NSURL fileURLWithPath:NSHomeDirectory()]];
    [openPanel beginSheetModalForWindow:self.window completionHandler:^(NSInteger result) {
        [openPanel close];
        if (result == NSFileHandlingPanelOKButton) {
            fileURL = [[openPanel URLs] objectAtIndex:0];
            action = upload;
            [self runAction];
        } else {
            action = nothing;
        }
    }];
}

- (IBAction)pushDownloadAFile:(id)sender {
    [NSApp beginSheet:self.downloadFilePanel modalForWindow:self.window modalDelegate:self didEndSelector:@selector(didEndSheet:returnCode:contextInfo:) contextInfo:nil];
}

- (IBAction)downloadAFile:(id)sender {
    [NSApp endSheet:self.downloadFilePanel];
    //    [self.downloadFilePanel close];
    //    [self.downloadFilePanel orderOut:self];
    action = download;
    [self runAction];
}

- (IBAction)pushListFiles:(id)sender {
    action = list;
    [self runAction];
}

- (IBAction)pushCreateADirectory:(id)sender {
    [NSApp beginSheet:self.directoryPanel modalForWindow:self.window modalDelegate:self didEndSelector:@selector(didEndSheet:returnCode:contextInfo:) contextInfo:nil];
}

- (IBAction)createADirectory:(id)sender {
    [NSApp endSheet:self.directoryPanel];
    action = newfolder;
    [self runAction];
}
- (IBAction)pushDeleteAFile:(id)sender {
    [NSApp beginSheet:self.deletePanel modalForWindow:self.window modalDelegate:self didEndSelector:@selector(didEndSheet:returnCode:contextInfo:) contextInfo:nil];
}
- (IBAction)confirmDeleteAFile:(id)sender {
    [NSApp endSheet:self.deletePanel];
    action = del;
    [self runAction];
}
- (IBAction)pushChmod:(id)sender {
    [NSApp beginSheet:self.chmodPanel modalForWindow:self.window modalDelegate:self didEndSelector:@selector(didEndSheet:returnCode:contextInfo:) contextInfo:nil];
}
- (IBAction)confirmChmod:(id)sender {
    [NSApp endSheet:self.chmodPanel];
    action = chmod;
    [self runAction];
}

- (IBAction)abort:(id)sender {
    if (ftpManager) {
        aborted = YES;
        [ftpManager abort];
    }
}

#pragma mark - dismiss panels

- (IBAction)dismissDownloadPanel:(id)sender {
    [NSApp endSheet:self.downloadFilePanel];
}
- (IBAction)dismissDirectoryPanel:(id)sender {
    [NSApp endSheet:self.directoryPanel];
}
- (IBAction)dismissFolderOutputPanel:(id)sender {
    [NSApp endSheet:self.fileListOutputPanel];
}
- (IBAction)dismissDeletePanel:(id)sender {
    [NSApp endSheet:self.deletePanel];
}
- (IBAction)dismissChmodPanel:(id)sender {
    [NSApp endSheet:self.chmodPanel];
}


@end

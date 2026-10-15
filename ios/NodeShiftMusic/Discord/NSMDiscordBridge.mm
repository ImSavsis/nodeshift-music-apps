#import "NSMDiscordBridge.h"

#include <memory>
#include <string>

#if __has_include(<discord_partner_sdk/discordpp.h>)
#define DISCORDPP_IMPLEMENTATION
#import <discord_partner_sdk/discordpp.h>
#define NSM_HAS_DISCORD_SDK 1
#else
#define NSM_HAS_DISCORD_SDK 0
#endif

static NSString *NSMText(const std::string &value) {
    NSString *text = [NSString stringWithUTF8String:value.c_str()];
    return text ?: @"";
}

static std::string NSMUtf8(NSString *value) {
    const char *bytes = value.UTF8String;
    return bytes ? std::string(bytes) : std::string();
}

#if NSM_HAS_DISCORD_SDK

@interface NSMDiscordBridge () {
    std::shared_ptr<discordpp::Client> _client;
    uint64_t _applicationId;
    NSTimer *_timer;
    BOOL _ready;
}
@end

@implementation NSMDiscordBridge

+ (NSMDiscordBridge *)shared {
    static NSMDiscordBridge *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[NSMDiscordBridge alloc] init];
    });
    return instance;
}

- (BOOL)available {
    return YES;
}

- (BOOL)ready {
    return _ready;
}

- (void)configure:(uint64_t)applicationId {
    if (_client && _applicationId == applicationId) {
        return;
    }
    _applicationId = applicationId;
    _ready = NO;
    _client = std::make_shared<discordpp::Client>();
    _client->SetApplicationId(applicationId);
    NSMDiscordBridge *bridge = self;
    _client->SetStatusChangedCallback([bridge](discordpp::Client::Status status, discordpp::Client::Error, int32_t) {
        BOOL ready = status == discordpp::Client::Status::Ready;
        bridge->_ready = ready;
        void (^handler)(BOOL) = bridge.onStatusChange;
        if (handler) {
            handler(ready);
        }
    });
    if (!_timer) {
        _timer = [NSTimer timerWithTimeInterval:0.1
                                        repeats:YES
                                          block:^(NSTimer *timer) {
                                              discordpp::RunCallbacks();
                                          }];
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    }
}

- (void)authorize:(NSMDiscordTokenBlock)completion {
    if (!_client) {
        completion(nil, nil, 0, @"sdk is not configured");
        return;
    }
    std::weak_ptr<discordpp::Client> weak = _client;
    uint64_t applicationId = _applicationId;
    auto verifier = std::make_shared<discordpp::AuthorizationCodeVerifier>(_client->CreateAuthorizationCodeVerifier());
    discordpp::AuthorizationArgs args;
    args.SetClientId(applicationId);
    args.SetScopes(discordpp::Client::GetDefaultPresenceScopes());
    args.SetCodeChallenge(verifier->Challenge());
    _client->Authorize(args, [weak, applicationId, verifier, completion](discordpp::ClientResult result, std::string code, std::string redirectUri) {
        if (!result.Successful()) {
            completion(nil, nil, 0, NSMText(result.Error()));
            return;
        }
        std::shared_ptr<discordpp::Client> client = weak.lock();
        if (!client) {
            completion(nil, nil, 0, @"sdk was released");
            return;
        }
        client->GetToken(applicationId, code, verifier->Verifier(), redirectUri,
                         [completion](discordpp::ClientResult tokenResult, std::string accessToken, std::string refreshToken,
                                      discordpp::AuthorizationTokenType, int32_t expiresIn, std::string) {
                             if (!tokenResult.Successful()) {
                                 completion(nil, nil, 0, NSMText(tokenResult.Error()));
                                 return;
                             }
                             completion(NSMText(accessToken), NSMText(refreshToken), expiresIn, nil);
                         });
    });
}

- (void)refresh:(NSString *)refreshToken completion:(NSMDiscordTokenBlock)completion {
    if (!_client) {
        completion(nil, nil, 0, @"sdk is not configured");
        return;
    }
    _client->RefreshToken(_applicationId, NSMUtf8(refreshToken),
                          [completion](discordpp::ClientResult result, std::string accessToken, std::string newRefresh,
                                       discordpp::AuthorizationTokenType, int32_t expiresIn, std::string) {
                              if (!result.Successful()) {
                                  completion(nil, nil, 0, NSMText(result.Error()));
                                  return;
                              }
                              completion(NSMText(accessToken), NSMText(newRefresh), expiresIn, nil);
                          });
}

- (void)connect:(NSString *)accessToken completion:(NSMDiscordResultBlock)completion {
    if (!_client) {
        completion(NO, YES, @"sdk is not configured");
        return;
    }
    std::weak_ptr<discordpp::Client> weak = _client;
    _client->UpdateToken(discordpp::AuthorizationTokenType::Bearer, NSMUtf8(accessToken),
                         [weak, completion](discordpp::ClientResult result) {
                             if (!result.Successful()) {
                                 completion(NO, result.Retryable(), NSMText(result.Error()));
                                 return;
                             }
                             std::shared_ptr<discordpp::Client> client = weak.lock();
                             if (client) {
                                 client->Connect();
                             }
                             completion(YES, NO, nil);
                         });
}

- (void)publish:(NSDictionary<NSString *, id> *)info completion:(NSMDiscordResultBlock)completion {
    if (!_client || !_ready) {
        completion(NO, YES, @"discord is not ready");
        return;
    }
    NSString *name = info[@"name"];
    NSString *title = info[@"title"];
    NSString *artist = info[@"artist"];
    NSString *album = info[@"album"];
    NSString *cover = info[@"cover"];
    NSString *page = info[@"page"];
    NSString *pageLabel = info[@"pageLabel"];
    uint64_t start = [info[@"start"] unsignedLongLongValue];
    uint64_t end = [info[@"end"] unsignedLongLongValue];

    discordpp::Activity activity;
    activity.SetType(discordpp::ActivityTypes::Listening);
    activity.SetName(NSMUtf8(name));
    activity.SetStatusDisplayType(discordpp::StatusDisplayTypes::Name);
    activity.SetApplicationId(_applicationId);
    activity.SetDetails(NSMUtf8(title));
    if (artist.length > 0) {
        activity.SetState(NSMUtf8(artist));
    }
    if (page.length > 0) {
        activity.SetDetailsUrl(NSMUtf8(page));
        discordpp::ActivityButton button;
        button.SetLabel(NSMUtf8(pageLabel.length > 0 ? pageLabel : @"Открыть трек"));
        button.SetUrl(NSMUtf8(page));
        activity.AddButton(button);
    }
    discordpp::ActivityAssets assets;
    if (cover.length > 0) {
        assets.SetLargeImage(NSMUtf8(cover));
    }
    if (album.length > 0) {
        assets.SetLargeText(NSMUtf8(album));
    }
    activity.SetAssets(assets);
    if (end > start) {
        discordpp::ActivityTimestamps timestamps;
        timestamps.SetStart(start);
        timestamps.SetEnd(end);
        activity.SetTimestamps(timestamps);
    }
    _client->UpdateRichPresence(activity, [completion](discordpp::ClientResult result) {
        completion(result.Successful(), result.Retryable(), result.Successful() ? nil : NSMText(result.Error()));
    });
}

- (void)clearPresence {
    if (_client && _ready) {
        _client->ClearRichPresence();
    }
}

- (void)disconnect {
    if (_client) {
        _client->Disconnect();
    }
    _ready = NO;
}

@end

#else

@implementation NSMDiscordBridge

+ (NSMDiscordBridge *)shared {
    static NSMDiscordBridge *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[NSMDiscordBridge alloc] init];
    });
    return instance;
}

- (BOOL)available {
    return NO;
}

- (BOOL)ready {
    return NO;
}

- (void)configure:(uint64_t)applicationId {
}

- (void)authorize:(NSMDiscordTokenBlock)completion {
    completion(nil, nil, 0, @"discord sdk is not linked");
}

- (void)refresh:(NSString *)refreshToken completion:(NSMDiscordTokenBlock)completion {
    completion(nil, nil, 0, @"discord sdk is not linked");
}

- (void)connect:(NSString *)accessToken completion:(NSMDiscordResultBlock)completion {
    completion(NO, NO, @"discord sdk is not linked");
}

- (void)publish:(NSDictionary<NSString *, id> *)activity completion:(NSMDiscordResultBlock)completion {
    completion(NO, NO, @"discord sdk is not linked");
}

- (void)clearPresence {
}

- (void)disconnect {
}

@end

#endif

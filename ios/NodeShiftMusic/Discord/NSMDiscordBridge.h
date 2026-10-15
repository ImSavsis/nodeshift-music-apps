#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^NSMDiscordTokenBlock)(NSString *_Nullable accessToken,
                                     NSString *_Nullable refreshToken,
                                     NSInteger expiresIn,
                                     NSString *_Nullable error);

typedef void (^NSMDiscordResultBlock)(BOOL ok, BOOL retryable, NSString *_Nullable error);

@interface NSMDiscordBridge : NSObject

@property(class, nonatomic, readonly) NSMDiscordBridge *shared;
@property(nonatomic, readonly) BOOL available;
@property(nonatomic, readonly) BOOL ready;
@property(nonatomic, copy, nullable) void (^onStatusChange)(BOOL ready);

- (void)configure:(uint64_t)applicationId;
- (void)authorize:(NSMDiscordTokenBlock)completion;
- (void)refresh:(NSString *)refreshToken completion:(NSMDiscordTokenBlock)completion;
- (void)connect:(NSString *)accessToken completion:(NSMDiscordResultBlock)completion;
- (void)publish:(NSDictionary<NSString *, id> *)activity completion:(NSMDiscordResultBlock)completion;
- (void)clearPresence;
- (void)disconnect;

@end

NS_ASSUME_NONNULL_END

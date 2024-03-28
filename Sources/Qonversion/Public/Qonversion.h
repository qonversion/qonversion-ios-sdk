#import <StoreKit/StoreKit.h>

#import "QONLaunchResult.h"
#import "QONProduct.h"
#import "QONEntitlement.h"
#import "QONOfferings.h"
#import "QONOffering.h"
#import "QONIntroEligibility.h"
#import "QONPromoPurchasesDelegate.h"
#import "QONEntitlementsUpdateListener.h"
#import "QONExperimentGroup.h"
#import "QONExperiment.h"
#import "QONRemoteConfig.h"
#import "QONRemoteConfigList.h"
#import "QONUser.h"
#import "QONErrors.h"
#import "QONStoreKitSugare.h"
#import "QONEntitlementsCacheLifetime.h"
#import "QONConfiguration.h"
#import "QONStoreKit2PurchaseModel.h"
#import "QONUserProperties.h"
#import "QONUserProperty.h"
#import "QONSubscriptionPeriod.h"

#if TARGET_OS_IOS
#import "QONAutomationsDelegate.h"
#import "QONAutomations.h"
#import "QONScreenCustomizationDelegate.h"
#endif

NS_ASSUME_NONNULL_BEGIN

static NSString *const QonversionErrorDomain = @"com.qonversion.io";
static NSString *const QonversionApiErrorDomain = @"com.qonversion.io.api";

@interface Qonversion : NSObject

/**
 Use `initWithConfig` instead.
 */
- (instancetype)init NS_UNAVAILABLE;

/**
 An entry point to use Qonversion SDK. Call to initialize Qonversion SDK with required and extra configs.
 The function is the best way to set additional configs you need to use Qonversion SDK.
 @param configuration a config that contains key SDK settings.
 @return Initialized instance of the Qonversion SDK.
 */
+ (instancetype)initWithConfig:(QONConfiguration *)configuration;

/**
 Use this variable to get a current initialized instance of the Qonversion SDK.
 Please, use the variable only after initializing the SDK.
 @return Current initialized instance of the Qonversion SDK.
 */
+ (instancetype)sharedInstance NS_SWIFT_NAME(shared());

/**
 Call this function to sync the subscriber data with the first launch when Qonversion is implemented.
 */
- (void)syncHistoricalData;

/**
 Call this function to link a user to his unique ID in your system and share purchase data.
 
 @param userID - unique user ID in your system
 */
- (void)identify:(NSString *)userID;

/**
 Call this function to unlink a user from his unique ID in your system and his purchase data.
 */
- (void)logout;

/**
 Set this listener to handle pending purchases like SCA, Ask to buy, etc
 The delegate will be called when the deferred transaction status updates
 @param listener - listener for handling deferred purchases
 */
- (void)setEntitlementsUpdateListener:(id<QONEntitlementsUpdateListener>)listener;

/**
 Set this delegate to handle AppStore promo purchases
 @param delegate - delegate for handling AppStore promo purchase flow
 */
- (void)setPromoPurchasesDelegate:(id<QONPromoPurchasesDelegate>)delegate;

/**
 Shows up a sheet for users to redeem AppStore offer codes
 */
- (void)presentCodeRedemptionSheet API_AVAILABLE(ios(14.0)) API_UNAVAILABLE(tvos, macos, watchos);

/**
 Sets Qonversion reserved user properties, like email or one-signal id.
 Note that using `QONUserPropertyKeyCustom` here will do nothing.
 To set custom user property, use `setCustomUserProperty` method instead.
 @param key - Defined enum key that will be transformed to string
 @param value - Property value
 */
- (void)setUserProperty:(QONUserPropertyKey)key value:(NSString *)value;

/**
 Sets custom user property
 @param key - Custom property key
 @param value - Property value
 */
- (void)setCustomUserProperty:(NSString *)key value:(NSString *)value;

/**
 This method returns all the properties, set for the current Qonversion user.
 All set properties are sent to the server with delay, so if you call
 this function right after setting some property, it may not be included
 in the result.
 @param completion - Completion block that will be called when response is received
 */
- (void)userProperties:(QONUserPropertiesCompletionHandler)completion;

/**
 Send your attribution data
 @param data Dictionary received by the provider
 @param provider Attribution provider
 */
- (void)attribution:(NSDictionary *)data fromProvider:(QONAttributionProvider)provider;

/**
 Check user entitlements
 @param completion Completion block that includes entitlements dictionary and error
 */
- (void)checkEntitlements:(QONEntitlementsCompletionHandler)completion;

/**
 Make a purchase and validate that through server-to-server using Qonversion's Backend
 
 @param product Product create in Qonversion Dash
 */
- (void)purchaseProduct:(QONProduct *)product completion:(QONPurchaseCompletionHandler)completion;

/**
 Make a purchase and validate that through server-to-server using Qonversion's Backend
 
 @param productID Product identifier create in Qonversion Dash, pay attention that you should use qonversion id instead Apple Product ID
 */
- (void)purchase:(NSString *)productID completion:(QONPurchaseCompletionHandler)completion;

/**
 Restore user entitlements based on purchases
 @param completion Completion block that includes entitlements dictionary and error
 */
- (void)restore:(QNRestoreCompletionHandler)completion;

/**
 Returns Qonversion Products in association with Store Kit Products
 If you get an empty SKProducts be sure your in-app purchases are correctly set up in AppStore Connect and .storeKit file is available.
 
 @see [Installing the iOS SDK](https://qonversion.io/docs/apple)
 */
- (void)products:(QONProductsCompletionHandler)completion;

/**
 You can check if a user is eligible for an introductory offer, including a free trial.
 On the Apple platform, users who have not previously used an introductory offer for any products
 in the same subscription group are eligible for an introductory offer. Use this method to determine eligibility.
 
 You can show only a regular price for users who are not eligible for an introductory offer.
 @param productIds products identifiers that must be checked
 @param completion Completion block that includes trial eligibility check result dictionary and error
 */
- (void)checkTrialIntroEligibility:(NSArray<NSString *> *)productIds completion:(QONEligibilityCompletionHandler)completion;

/**
 Returns Qonversion Offerings Object
 
 An offering is a group of products that you can offer to a user on a given paywall based on your business logic.
 For example, you can offer one set of products on a paywall immediately after onboarding and another set of products
 with discounts later on if a user has not converted.
 Offerings allow changing the products offered remotely without releasing app updates.
 
 @see [Offerings](https://qonversion.io/docs/offerings)
 @param completion Completion block that includes information about the offerings user and error
 */
- (void)offerings:(QONOfferingsCompletionHandler)completion;

/**
 Information about the current Qonversion user
 @param completion Completion block that includes information about the current user and error
 */
- (void)userInfo:(QONUserInfoCompletionHandler)completion;

/**
 Enable attribution collection from Apple Search Ads
 */
- (void)collectAppleSearchAdsAttribution;

/**
 On iOS 14.5+, after requesting the app tracking permission using ATT, you need to notify Qonversion
 if tracking is allowed and IDFA is available.
 For Qonversion/NoIdfa SDK advertising ID is always empty.
 */
- (void)collectAdvertisingId;

/**
 Returns default Qonversion remote config object
 Use this function to get the remote config with specific payload and experiment info.
 @param completion completion block that includes information about the remote config.
 */
- (void)remoteConfig:(QONRemoteConfigCompletionHandler)completion;

/**
 Returns Qonversion remote config object by context key.
 Use this function to get the remote config with specific payload and experiment info.
 @param contextKey context key to load remote config for.
 @param completion completion block that includes information about the remote config.
 */
- (void)remoteConfig:(NSString *)contextKey completion:(QONRemoteConfigCompletionHandler)completion
NS_SWIFT_NAME(remoteConfig(contextKey:completion:));

/**
 Returns Qonversion remote config objects by a list of context keys.
 Use this function to get the remote configs with specific payload and experiment info.
 @param contextKeys list of context keys to load remote configs for.
 @param includeEmptyContextKey - set to true if you want to include remote config with empty context key to the result
 @param completion completion block that includes information about the loaded remote configs.
 */
- (void)remoteConfigList:(NSArray<NSString *> *)contextKeys includeEmptyContextKey:(BOOL)includeEmptyContextKey completion:(QONRemoteConfigListCompletionHandler)completion
NS_SWIFT_NAME(remoteConfigList(contextKeys:includeEmptyContextKey:completion:));

/**
 Returns Qonversion remote config objects for all existing context key (including empty one).
 Use this function to get the remote configs with specific payload and experiment info.
 @param completion completion block that includes information about the loaded remote configs.
 */
- (void)remoteConfigList:(QONRemoteConfigListCompletionHandler)completion;

/**
 This function should be used for the test purposes only.
 Do not forget to delete the usage of this function before the release.
 Use this function to attach the user to the remote configuration.
 @param remoteConfigurationId identifier of the remote configuration
 @param completion completion block that includes information about the result of the action. Success flag or error.
 */
- (void)attachUserToRemoteConfiguration:(NSString *)remoteConfigurationId completion:(QONRemoteConfigurationAttachCompletionHandler)completion;

/**
 This function should be used for the test purposes only.
 Do not forget to delete the usage of this function before the release.
 Use this function to detach the user from the remote configuration.
 @param remoteConfigurationId identifier of the remote configuration
 @param completion completion block that includes information about the result of the action. Success flag or error.
 */
- (void)detachUserFromRemoteConfiguration:(NSString *)remoteConfigurationId completion:(QONRemoteConfigurationAttachCompletionHandler)completion;

/**
 This function should be used for the test purpose only.
 Do not forget to delete the usage of this function before the release.
 Use this function to attach the user to the experiment.
 @param experimentId identifier of the experiment
 @param groupId identifier of the experiment group
 @param completion completion block that includes information about the result of the action. Success flag or error.
 */
- (void)attachUserToExperiment:(NSString *)experimentId groupId:(NSString *)groupId completion:(QONExperimentAttachCompletionHandler)completion;

/**
 This function should be used for the test purpose only.
 Do not forget to delete the usage of this function before the release.
 Use this function to detach the user from the experiment.
 @param experimentId identifier of the experiment
 @param completion completion block that includes information about the result of the action. Success flag or error.
 */
- (void)detachUserFromExperiment:(NSString *)experimentId completion:(QONExperimentAttachCompletionHandler)completion;

/**
 Contact us before you start using this function.
 Handles purchases for StoreKit2 if you are using Qonversion in the Analytics Mode.
 @param purchasesInfo array of StoreKit2 purchases models
 */
- (void)handlePurchases:(NSArray<QONStoreKit2PurchaseModel *> *)purchasesInfo;

/**
 Contact us before you start using this function.
 Handles purchases for StoreKit2 if you are using Qonversion in the Analytics Mode.
 @param purchasesInfo array of StoreKit2 purchases models
 @param completion completion block that includes information about the result of the action. Success flag or error.
 */
- (void)handlePurchases:(NSArray<QONStoreKit2PurchaseModel *> *)purchasesInfo completion:(nullable QONDefaultCompletionHandler)completion;

@end

NS_ASSUME_NONNULL_END

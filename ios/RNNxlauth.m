#import "RNNxlauth.h"
//#import <AppAuth/AppAuth.h>
#import <NXLAuth/NXLAuth.h>
#import <React/RCTLog.h>
#import <React/RCTConvert.h>
#import "RNNxlauthAuthorizationFlowManager.h"

@interface RNNxlauth()<RNNxlauthAuthorizationFlowManagerDelegate, OIDAuthStateChangeDelegate> {
    id<OIDExternalUserAgentSession> _currentSession;
}
@end

static NSString *const kCurrentAuthStateKey = @"currentAuthState";

@implementation RNNxlauth

-(BOOL)resumeExternalUserAgentFlowWithURL:(NSURL *)url {
    return [_currentSession resumeExternalUserAgentFlowWithURL:url];
}

- (void)loadAuthState {
    // loads OIDAuthState from NSUSerDefaults
    NSLog(@"[RN Lib] Load Current AuthState");
    NSData *archivedAuthState =
    [[NSUserDefaults standardUserDefaults] objectForKey:kCurrentAuthStateKey];
    OIDAuthState *authState = [NSKeyedUnarchiver unarchiveObjectWithData:archivedAuthState];
    if (!authState) {
        NSLog(@"[RN Lib] Load Previous State: %@", nil);
    } else {
        NSLog(@"[RN Lib] Load Previous State Success");
    }
    [self setAuthState:authState];
}

//- (dispatch_queue_t)methodQueue
//{
//    return dispatch_get_main_queue();
//}

RCT_EXPORT_MODULE()

RCT_REMAP_METHOD(authorizeRequest,
                 scopes: (NSArray *) scopes
                 resolve: (RCTPromiseResolveBlock) resolve
                 reject: (RCTPromiseRejectBlock)  reject)
{
    // if we have manually provided configuration, we can use it and skip the OIDC well-known discovery endpoint call
    //    dispatch_async(dispatch_get_main_queue(), ^{
    //        // do work here
    //    });
    NXLAppAuthManager *nexMng = [[NXLAppAuthManager alloc] init];
    NSArray *scopess = @[ ScopeOpenID, ScopeOffline];
    
    [nexMng authRequest:scopes :^(OIDAuthorizationRequest *request){
        dispatch_async(dispatch_get_main_queue(), ^{
            id<UIApplicationDelegate, RNNxlauthAuthorizationFlowManager> appDelegate = (id<UIApplicationDelegate, RNNxlauthAuthorizationFlowManager>)[UIApplication sharedApplication].delegate;
            if (![[appDelegate class] conformsToProtocol:@protocol(RNNxlauthAuthorizationFlowManager)]) {
                [NSException raise:@"RNNxlauth Missing protocol conformance"
                            format:@"%@ does not conform to RNNxlauthAuthorizationFlowManager", appDelegate];
            }
            appDelegate.authorizationFlowManagerDelegate = self;
            
            _currentSession = [nexMng authStateByPresentingAuthorizationRequest:request presentingViewController:appDelegate.window.rootViewController callback:^(OIDAuthState * _Nullable authState, NSError * _Nullable error) {
                NSLog(@"[Client] authState: %@", authState);
                NSLog(@"[Client] authorizationCode: %@", authState.lastAuthorizationResponse.authorizationCode);
                NSLog(@"[Client] accessToken: %@", authState.lastTokenResponse.accessToken);
                NSLog(@"[Client] idToken: %@", authState.lastTokenResponse.idToken);
                NSLog(@"[Client] refreshToken: %@", authState.lastTokenResponse.refreshToken);
                
                if (authState) {
                    resolve([self formatResponse:authState.lastTokenResponse]);
                    [self setAuthState:authState];
                } else {
                    reject(@"RNNxlauth Error", [error localizedDescription], error);
                    NSLog(@"error");
                }
            }];
        });
    }];
    
}

RCT_REMAP_METHOD(getUserInfo,
                 resolve: (RCTPromiseResolveBlock) resolve
                 reject: (RCTPromiseRejectBlock)  reject)
{
    NXLAppAuthManager *nexMng = [[NXLAppAuthManager alloc] init];
    [nexMng getUserInfo:^(NSDictionary * _Nonnull response) {
        if (response) {
            resolve(response);
        } else {
            resolve(@"Unable to retrieve User Info");
        }
    }];
    
    
}

RCT_REMAP_METHOD(getFreshToken, :(RCTPromiseResolveBlock) resolve :(RCTPromiseRejectBlock)  reject)
{
    NSString *currentAccessToken = _authState.lastTokenResponse.accessToken;
    NXLAppAuthManager *nexMng = [[NXLAppAuthManager alloc] init];
    [nexMng getFreshToken:^(NSString * _Nonnull accessToken, NSString * _Nonnull idToken, OIDAuthState * _Nonnull currentAuthState, NSError * _Nullable error) {
        [self setAuthState:currentAuthState];
        if (![currentAccessToken isEqual:accessToken]) {
            NSLog(@"[RNLib] Token refreshed");
            NSLog(@"Access token was refreshed automatically (%@ to %@)",
                  currentAccessToken,
                  accessToken);
            
        } else {
            NSLog(@"[RNLib] Token still valid");
            NSLog(@"Access token was fresh and not updated [%@]", accessToken);
        }
        resolve(accessToken);
        
    }];
}

RCT_EXPORT_METHOD(clearAuthState)
{
    [self setAuthState:nil];
    NXLAppAuthManager *nexMng = [[NXLAppAuthManager alloc] init];
    [nexMng clearAuthState];
}

RCT_REMAP_METHOD(getAuthState, state: (RCTPromiseResolveBlock) resolve
                 error: (RCTPromiseRejectBlock)  reject)
{
    // loads OIDAuthState from NSUSerDefaults
    NSLog(@"[RN Lib] Get Current AuthState");
    NSData *archivedAuthState =
    [[NSUserDefaults standardUserDefaults] objectForKey:kCurrentAuthStateKey];
    OIDAuthState *authState = [NSKeyedUnarchiver unarchiveObjectWithData:archivedAuthState];
    //    NSLog(@">>>>authState: %@", [self formatResponse:authState.lastTokenResponse]);
    if (!authState) {
        NSLog(@"[RN Lib] Load Previous State: %@", nil);
        resolve(@"");
    } else {
        NSLog(@"[RN Lib] Load Previous State Success");
        NSLog(@">>>>authState: %@", [self formatResponse:authState.lastTokenResponse]);
        resolve([self formatResponse:authState.lastTokenResponse]);
    }
    [self setAuthState:authState];
}


RCT_REMAP_METHOD(authorize,
                 issuer: (NSString *) issuer
                 redirectUrl: (NSString *) redirectUrl
                 clientId: (NSString *) clientId
                 clientSecret: (NSString *) clientSecret
                 scopes: (NSArray *) scopes
                 additionalParameters: (NSDictionary *_Nullable) additionalParameters
                 serviceConfiguration: (NSDictionary *_Nullable) serviceConfiguration
                 resolve: (RCTPromiseResolveBlock) resolve
                 reject: (RCTPromiseRejectBlock)  reject)
{
    // if we have manually provided configuration, we can use it and skip the OIDC well-known discovery endpoint call
    if (serviceConfiguration) {
        OIDServiceConfiguration *configuration = [self createServiceConfiguration:serviceConfiguration];
        [self authorizeWithConfiguration: configuration
                             redirectUrl: redirectUrl
                                clientId: clientId
                            clientSecret: clientSecret
                                  scopes: scopes
                    additionalParameters: additionalParameters
                                 resolve: resolve
                                  reject: reject];
    } else {
        [OIDAuthorizationService discoverServiceConfigurationForIssuer:[NSURL URLWithString:issuer]
                                                            completion:^(OIDServiceConfiguration *_Nullable configuration, NSError *_Nullable error) {
                                                                if (!configuration) {
                                                                    reject(@"RNAppAuth Error", [error localizedDescription], error);
                                                                    return;
                                                                }
                                                                [self authorizeWithConfiguration: configuration
                                                                                     redirectUrl: redirectUrl
                                                                                        clientId: clientId
                                                                                    clientSecret: clientSecret
                                                                                          scopes: scopes
                                                                            additionalParameters: additionalParameters
                                                                                         resolve: resolve
                                                                                          reject: reject];
                                                            }];
    }
} // end RCT_REMAP_METHOD(authorize,

RCT_REMAP_METHOD(refresh,
                 issuer: (NSString *) issuer
                 redirectUrl: (NSString *) redirectUrl
                 clientId: (NSString *) clientId
                 clientSecret: (NSString *) clientSecret
                 refreshToken: (NSString *) refreshToken
                 scopes: (NSArray *) scopes
                 additionalParameters: (NSDictionary *_Nullable) additionalParameters
                 serviceConfiguration: (NSDictionary *_Nullable) serviceConfiguration
                 resolve:(RCTPromiseResolveBlock) resolve
                 reject: (RCTPromiseRejectBlock)  reject)
{
    // if we have manually provided configuration, we can use it and skip the OIDC well-known discovery endpoint call
    if (serviceConfiguration) {
        OIDServiceConfiguration *configuration = [self createServiceConfiguration:serviceConfiguration];
        [self refreshWithConfiguration: configuration
                           redirectUrl: redirectUrl
                              clientId: clientId
                          clientSecret: clientSecret
                          refreshToken: refreshToken
                                scopes: scopes
                  additionalParameters: additionalParameters
                               resolve: resolve
                                reject: reject];
    } else {
        // otherwise hit up the discovery endpoint
        [OIDAuthorizationService discoverServiceConfigurationForIssuer:[NSURL URLWithString:issuer]
                                                            completion:^(OIDServiceConfiguration *_Nullable configuration, NSError *_Nullable error) {
                                                                if (!configuration) {
                                                                    reject(@"RNAppAuth Error", [error localizedDescription], error);
                                                                    return;
                                                                }
                                                                [self refreshWithConfiguration: configuration
                                                                                   redirectUrl: redirectUrl
                                                                                      clientId: clientId
                                                                                  clientSecret: clientSecret
                                                                                  refreshToken: refreshToken
                                                                                        scopes: scopes
                                                                          additionalParameters: additionalParameters
                                                                                       resolve: resolve
                                                                                        reject: reject];
                                                            }];
    }
} // end RCT_REMAP_METHOD(refresh,

//- (void)setAuthState:(nullable OIDAuthState *)authState {
//    NSLog(@"[Client] setAuthState");
//    if (_authState == authState) {
//        return;
//    }
//    _authState = authState;
//    //    if (authState != nil) {
//    //        [self performSegueWithIdentifier:@"login_success" sender:self];
//    //    }
//
//    _authState.stateChangeDelegate = self;
////
////    [self saveState];
////    [self updateUI];
//}


/*
 * Create a OIDServiceConfiguration from passed serviceConfiguration dictionary
 */
- (OIDServiceConfiguration *) createServiceConfiguration: (NSDictionary *) serviceConfiguration {
    NSURL *authorizationEndpoint = [NSURL URLWithString: [serviceConfiguration objectForKey:@"authorizationEndpoint"]];
    NSURL *tokenEndpoint = [NSURL URLWithString: [serviceConfiguration objectForKey:@"tokenEndpoint"]];
    NSURL *registrationEndpoint = [NSURL URLWithString: [serviceConfiguration objectForKey:@"registrationEndpoint"]];
    
    OIDServiceConfiguration *configuration =
    [[OIDServiceConfiguration alloc]
     initWithAuthorizationEndpoint:authorizationEndpoint
     tokenEndpoint:tokenEndpoint
     registrationEndpoint:registrationEndpoint];
    
    return configuration;
}

/*
 * Authorize a user in exchange for a token with provided OIDServiceConfiguration
 */
- (void)authorizeWithConfiguration: (OIDServiceConfiguration *) configuration
                       redirectUrl: (NSString *) redirectUrl
                          clientId: (NSString *) clientId
                      clientSecret: (NSString *) clientSecret
                            scopes: (NSArray *) scopes
              additionalParameters: (NSDictionary *_Nullable) additionalParameters
                           resolve: (RCTPromiseResolveBlock) resolve
                            reject: (RCTPromiseRejectBlock)  reject
{
    // builds authentication request
    OIDAuthorizationRequest *request =
    [[OIDAuthorizationRequest alloc] initWithConfiguration:configuration
                                                  clientId:clientId
                                              clientSecret:clientSecret
                                                    scopes:scopes
                                               redirectURL:[NSURL URLWithString:redirectUrl]
                                              responseType:OIDResponseTypeCode
                                      additionalParameters:additionalParameters];
    
    // performs authentication request
    id<UIApplicationDelegate, RNNxlauthAuthorizationFlowManager> appDelegate = (id<UIApplicationDelegate, RNNxlauthAuthorizationFlowManager>)[UIApplication sharedApplication].delegate;
    if (![[appDelegate class] conformsToProtocol:@protocol(RNNxlauthAuthorizationFlowManager)]) {
        [NSException raise:@"RNAppAuth Missing protocol conformance"
                    format:@"%@ does not conform to RNAppAuthAuthorizationFlowManager", appDelegate];
    }
    appDelegate.authorizationFlowManagerDelegate = self;
    __weak typeof(self) weakSelf = self;
    _currentSession = [OIDAuthState authStateByPresentingAuthorizationRequest:request
                                                     presentingViewController:appDelegate.window.rootViewController
                                                                     callback:^(OIDAuthState *_Nullable authState,
                                                                                NSError *_Nullable error) {
                                                                         typeof(self) strongSelf = weakSelf;
                                                                         strongSelf->_currentSession = nil;
                                                                         if (authState) {
                                                                             resolve([self formatResponse:authState.lastTokenResponse]);
                                                                         } else {
                                                                             reject(@"RNAppAuth Error", [error localizedDescription], error);
                                                                         }
                                                                     }]; // end [OIDAuthState authStateByPresentingAuthorizationRequest:request
}


/*
 * Refresh a token with provided OIDServiceConfiguration
 */
- (void)refreshWithConfiguration: (OIDServiceConfiguration *)configuration
                     redirectUrl: (NSString *) redirectUrl
                        clientId: (NSString *) clientId
                    clientSecret: (NSString *) clientSecret
                    refreshToken: (NSString *) refreshToken
                          scopes: (NSArray *) scopes
            additionalParameters: (NSDictionary *_Nullable) additionalParameters
                         resolve:(RCTPromiseResolveBlock) resolve
                          reject: (RCTPromiseRejectBlock)  reject {
    
    OIDTokenRequest *tokenRefreshRequest =
    [[OIDTokenRequest alloc] initWithConfiguration:configuration
                                         grantType:@"refresh_token"
                                 authorizationCode:nil
                                       redirectURL:[NSURL URLWithString:redirectUrl]
                                          clientID:clientId
                                      clientSecret:clientSecret
                                            scopes:scopes
                                      refreshToken:refreshToken
                                      codeVerifier:nil
                              additionalParameters:additionalParameters];
    
    [OIDAuthorizationService performTokenRequest:tokenRefreshRequest
                                        callback:^(OIDTokenResponse *_Nullable response,
                                                   NSError *_Nullable error) {
                                            if (response) {
                                                resolve([self formatResponse:response]);
                                            } else {
                                                reject(@"RNAppAuth Error", [error localizedDescription], error);
                                            }
                                        }];
}

/*
 * Take raw OIDTokenResponse and turn it to a token response format to pass to JavaScript caller
 */
- (NSDictionary*)formatResponse: (OIDTokenResponse*) response {
    NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
    dateFormat.timeZone = [NSTimeZone timeZoneWithAbbreviation: @"UTC"];
    [dateFormat setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    [dateFormat setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
    
    return @{@"accessToken": response.accessToken ? response.accessToken : @"",
             @"accessTokenExpirationDate": response.accessTokenExpirationDate ? [dateFormat stringFromDate:response.accessTokenExpirationDate] : @"",
             @"additionalParameters": response.additionalParameters,
             @"idToken": response.idToken ? response.idToken : @"",
             @"refreshToken": response.refreshToken ? response.refreshToken : @"",
             @"tokenType": response.tokenType ? response.tokenType : @"",
             };
}

- (void)didChangeState:(nonnull OIDAuthState *)state {
    NSLog(@"SSSSSSSState change");
}

@end


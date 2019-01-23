/*
 * Copyright @ 2017-present Atlassian Pty Ltd
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <Intents/Intents.h>

#include <mach/mach_time.h>

#import <React/RCTAssert.h>
#import <React/RCTLinkingManager.h>
#import <React/RCTRootView.h>

#import <RNGoogleSignin/RNGoogleSignin.h>

#import "Dropbox.h"
#import "JitsiMeetView+Private.h"
#import "RCTBridgeWrapper.h"

/**
 * A `RCTFatalHandler` implementation which swallows JavaScript errors. In the
 * Release configuration, React Native will (intentionally) raise an unhandled
 * `NSException` for an unhandled JavaScript error. This will effectively kill
 * the application. `_RCTFatal` is suitable to be in accord with the Web i.e.
 * not kill the application.
 */
RCTFatalHandler _RCTFatal = ^(NSError *error) {
    id jsStackTrace = error.userInfo[RCTJSStackTraceKey];
    @try {
        NSString *name
            = [NSString stringWithFormat:@"%@: %@",
                        RCTFatalExceptionName,
                        error.localizedDescription];
        NSString *message
            = RCTFormatError(error.localizedDescription, jsStackTrace, 75);
        [NSException raise:name format:@"%@", message];
    } @catch (NSException *e) {
        if (!jsStackTrace) {
            @throw;
        }
    }
};

/**
 * Helper function to register a fatal error handler for React. Our handler
 * won't kill the process, it will swallow JS errors and print stack traces
 * instead.
 */
void registerFatalErrorHandler() {
#if !DEBUG
    // In the Release configuration, React Native will (intentionally) raise an
    // unhandled `NSException` for an unhandled JavaScript error. This will
    // effectively kill the application. In accord with the Web, do not kill the
    // application.
    if (!RCTGetFatalHandler()) {
        RCTSetFatalHandler(_RCTFatal);
    }
#endif
}

@interface JitsiMeetView() {
    /**
     * The unique identifier of this `JitsiMeetView` within the process for the
     * purposes of `ExternalAPI`. The name scope was inspired by postis which we
     * use on Web for the similar purposes of the iframe-based external API.
     */
    NSString *externalAPIScope;

    RCTRootView *rootView;
}

@end

@implementation JitsiMeetView {
    NSNumber *_pictureInPictureEnabled;
}

@dynamic pictureInPictureEnabled;

static NSString *_conferenceActivityType;

static RCTBridgeWrapper *bridgeWrapper;

/**
 * The `JitsiMeetView`s associated with their `ExternalAPI` scopes (i.e. unique
 * identifiers within the process).
 */
static NSMapTable<NSString *, JitsiMeetView *> *views;

+             (BOOL)application:(UIApplication *)application
  didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [Dropbox setAppKey];

    return YES;
}

#pragma mark Linking delegate helpers

+    (BOOL)application:(UIApplication *)application
  continueUserActivity:(NSUserActivity *)userActivity
    restorationHandler:(void (^)(NSArray *restorableObjects))restorationHandler
{
    id url = [self conferenceURLFromUserActivity:userActivity];

    return url && [self loadURLObjectInViews:url];
}

+ (BOOL)application:(UIApplication *)app
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    if ([Dropbox application:app openURL:url options:options]) {
        return YES;
    }

    if ([RNGoogleSignin application:app
                            openURL:url
                  sourceApplication:options[UIApplicationOpenURLOptionsSourceApplicationKey]
                         annotation:options[UIApplicationOpenURLOptionsAnnotationKey]]) {
        return YES;
    }

    return [self loadURLInViews:url];
}

#pragma mark Initializers

- (instancetype)init {
    self = [super init];
    if (self) {
        [self initWithXXX];
    }

    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self initWithXXX];
    }

    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self initWithXXX];
    }

    return self;
}

#pragma mark API

/**
 * Loads a specific `NSURL` which may identify a conference to join. If the
 * specified `NSURL` is `nil` and the Welcome page is enabled, the Welcome page
 * is displayed instead.
 *
 * @param url The `NSURL` to load which may identify a conference to join.
 */
- (void)loadURL:(NSURL *)url {
    [self loadURLString:url ? url.absoluteString : nil];
}

/**
 * Loads a specific URL which may identify a conference to join. The URL is
 * specified in the form of an `NSDictionary` of properties which (1)
 * internally are sufficient to construct a URL `NSString` while (2) abstracting
 * the specifics of constructing the URL away from API clients/consumers. If the
 * specified URL is `nil` and the Welcome page is enabled, the Welcome page is
 * displayed instead.
 *
 * @param urlObject The URL to load which may identify a conference to join.
 */
- (void)loadURLObject:(NSDictionary *)urlObject {
    NSMutableDictionary *props = [[NSMutableDictionary alloc] init];

    if (self.defaultURL) {
        props[@"defaultURL"] = [self.defaultURL absoluteString];
    }

    props[@"externalAPIScope"] = externalAPIScope;
    props[@"pictureInPictureEnabled"] = @(self.pictureInPictureEnabled);
    props[@"welcomePageEnabled"] = @(self.welcomePageEnabled);

    // XXX If urlObject is nil, then it must appear as undefined in the
    // JavaScript source code so that we check the launchOptions there.
    if (urlObject) {
        props[@"url"] = urlObject;
    }

    // XXX The method loadURLObject: is supposed to be imperative i.e. a second
    // invocation with one and the same URL is expected to join the respective
    // conference again if the first invocation was followed by leaving the
    // conference. However, React and, respectively,
    // appProperties/initialProperties are declarative expressions i.e. one and
    // the same URL will not trigger an automatic re-render in the JavaScript
    // source code. The workaround implemented bellow introduces imperativeness
    // in React Component props by defining a unique value per loadURLObject:
    // invocation.
    props[@"timestamp"] = @(mach_absolute_time());

    if (rootView) {
        // Update props with the new URL.
        rootView.appProperties = props;
    } else {
        rootView
            = [[RCTRootView alloc] initWithBridge:bridgeWrapper.bridge
                                       moduleName:@"App"
                                initialProperties:props];
        rootView.backgroundColor = self.backgroundColor;

        // Add rootView as a subview which completely covers this one.
        [rootView setFrame:[self bounds]];
        rootView.autoresizingMask
            = UIViewAutoresizingFlexibleWidth
                | UIViewAutoresizingFlexibleHeight;
        [self addSubview:rootView];
    }
}

/**
 * Loads a specific URL `NSString` which may identify a conference to
 * join. If the specified URL `NSString` is `nil` and the Welcome page is
 * enabled, the Welcome page is displayed instead.
 *
 * @param urlString The URL `NSString` to load which may identify a conference
 * to join.
 */
- (void)loadURLString:(NSString *)urlString {
    [self loadURLObject:urlString ? @{ @"url": urlString } : nil];
}

#pragma conferenceActivityType getter / setter

+ (NSString *)conferenceActivityType {
    return _conferenceActivityType;
}

+ (void) setConferenceActivityType:(NSString *)conferenceActivityType {
    _conferenceActivityType = conferenceActivityType;
}

#pragma pictureInPictureEnabled getter / setter

- (void) setPictureInPictureEnabled:(BOOL)pictureInPictureEnabled {
    _pictureInPictureEnabled
        = [NSNumber numberWithBool:pictureInPictureEnabled];
}

- (BOOL) pictureInPictureEnabled {
    if (_pictureInPictureEnabled) {
        return [_pictureInPictureEnabled boolValue];
    }

    // The SDK/JitsiMeetView client/consumer did not explicitly enable/disable
    // Picture-in-Picture. However, we may automatically deduce their
    // intentions: we need the support of the client in order to implement
    // Picture-in-Picture on iOS (in contrast to Android) so if the client
    // appears to have provided the support then we can assume that they did it
    // with the intention to have Picture-in-Picture enabled.
    return self.delegate
        && [self.delegate respondsToSelector:@selector(enterPictureInPicture:)];
}

#pragma mark Private methods

/**
 * Loads a specific `NSURL` in all existing `JitsiMeetView`s.
 *
 * @param url The `NSURL` to load in all existing `JitsiMeetView`s.
 * @return `YES` if the specified `url` was submitted for loading in at least
 * one `JitsiMeetView`; otherwise, `NO`.
 */
+ (BOOL)loadURLInViews:(NSURL *)url {
    return
        [self loadURLObjectInViews:url ? @{ @"url": url.absoluteString } : nil];
}

+ (BOOL)loadURLObjectInViews:(NSDictionary *)urlObject {
    BOOL handled = NO;

    if (views) {
        for (NSString *externalAPIScope in views) {
            JitsiMeetView *view
                = [self viewForExternalAPIScope:externalAPIScope];

            if (view) {
                [view loadURLObject:urlObject];
                handled = YES;
            }
        }
    }

    return handled;
}

+ (NSDictionary *)conferenceURLFromLaunchOptions:(NSDictionary *)launchOptions {
    if (launchOptions[UIApplicationLaunchOptionsURLKey]) {
        NSURL *url = launchOptions[UIApplicationLaunchOptionsURLKey];
        return @{ @"url" : url.absoluteString };
    } else {
        NSDictionary *userActivityDictionary
            = launchOptions[UIApplicationLaunchOptionsUserActivityDictionaryKey];
        NSUserActivity *userActivity
            = [userActivityDictionary objectForKey:@"UIApplicationLaunchOptionsUserActivityKey"];
        if (userActivity != nil) {
            return [self conferenceURLFromUserActivity:userActivity];
        }
    }

    return nil;
}

+ (NSDictionary *)conferenceURLFromUserActivity:(NSUserActivity *)userActivity {
    NSString *activityType = userActivity.activityType;

    if ([activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {
        // App was started by opening a URL in the browser
        return @{ @"url" : userActivity.webpageURL.absoluteString };
    } else if ([activityType isEqualToString:@"INStartAudioCallIntent"]
               || [activityType isEqualToString:@"INStartVideoCallIntent"]) {
        // App was started by a CallKit Intent
        INIntent *intent = userActivity.interaction.intent;
        NSArray<INPerson *> *contacts;
        NSString *url;
        BOOL startAudioOnly = NO;

        if ([intent isKindOfClass:[INStartAudioCallIntent class]]) {
            contacts = ((INStartAudioCallIntent *) intent).contacts;
            startAudioOnly = YES;
        } else if ([intent isKindOfClass:[INStartVideoCallIntent class]]) {
            contacts = ((INStartVideoCallIntent *) intent).contacts;
        }

        if (contacts && (url = contacts.firstObject.personHandle.value)) {
            return @{
                @"config": @{@"startAudioOnly":@(startAudioOnly)},
                @"url": url
                };
        }
    } else if (_conferenceActivityType && [activityType isEqualToString:_conferenceActivityType]) {
        // App was started by continuing a registered NSUserActivity (SiriKit, Handoff, ...)
        NSString *url;

        if ((url = userActivity.userInfo[@"url"])) {
            return @{ @"url" : url };
        }
    }

    return nil;
}

+ (instancetype)viewForExternalAPIScope:(NSString *)externalAPIScope {
    return [views objectForKey:externalAPIScope];
}

/**
 * Internal initialization:
 *
 * - sets the background color
 * - creates the React bridge
 * - loads the necessary custom fonts
 * - registers a custom fatal error error handler for React
 */
- (void)initWithXXX {
    static dispatch_once_t dispatchOncePredicate;

    dispatch_once(&dispatchOncePredicate, ^{
        // Initialize the static state of JitsiMeetView.
        bridgeWrapper = [[RCTBridgeWrapper alloc] init];
        views = [NSMapTable strongToWeakObjectsMapTable];

        // Register a fatal error handler for React.
        registerFatalErrorHandler();
    });

    // Hook this JitsiMeetView into ExternalAPI.
    externalAPIScope = [NSUUID UUID].UUIDString;
    [views setObject:self forKey:externalAPIScope];

    // Set a background color which is in accord with the JavaScript and Android
    // parts of the application and causes less perceived visual flicker than
    // the default background color.
    self.backgroundColor
        = [UIColor colorWithRed:.07f green:.07f blue:.07f alpha:1];
}

@end

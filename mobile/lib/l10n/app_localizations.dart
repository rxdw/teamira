import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru')
  ];

  /// No description provided for @nothingPlantedYetTapWriteFirst.
  ///
  /// In en, this message translates to:
  /// **'nothing planted yet — tap + to write your first evening'**
  String get nothingPlantedYetTapWriteFirst;

  /// No description provided for @theRouteHasnTStartedYet.
  ///
  /// In en, this message translates to:
  /// **'the route hasn\'t started yet — tap + to write your first evening'**
  String get theRouteHasnTStartedYet;

  /// No description provided for @noTicketsYetTapWriteFirst.
  ///
  /// In en, this message translates to:
  /// **'no tickets yet — tap + to write your first evening'**
  String get noTicketsYetTapWriteFirst;

  /// No description provided for @noLaunchesYetTapWriteFirst.
  ///
  /// In en, this message translates to:
  /// **'no launches yet — tap + to write your first evening'**
  String get noLaunchesYetTapWriteFirst;

  /// No description provided for @stillRoad.
  ///
  /// In en, this message translates to:
  /// **'still on the road'**
  String get stillRoad;

  /// No description provided for @stillOutGarden.
  ///
  /// In en, this message translates to:
  /// **'still out in the garden'**
  String get stillOutGarden;

  /// No description provided for @stillAir.
  ///
  /// In en, this message translates to:
  /// **'still in the air'**
  String get stillAir;

  /// No description provided for @stillOrbit.
  ///
  /// In en, this message translates to:
  /// **'still in orbit'**
  String get stillOrbit;

  /// No description provided for @yourGardenBloom.
  ///
  /// In en, this message translates to:
  /// **'your garden in bloom'**
  String get yourGardenBloom;

  /// No description provided for @theWholeGardenBloomed.
  ///
  /// In en, this message translates to:
  /// **'the whole garden bloomed'**
  String get theWholeGardenBloomed;

  /// No description provided for @endLineWholeRouteDriven.
  ///
  /// In en, this message translates to:
  /// **'end of the line — whole route driven'**
  String get endLineWholeRouteDriven;

  /// No description provided for @thatSWrapWholeReelWatched.
  ///
  /// In en, this message translates to:
  /// **'that\'s a wrap — whole reel watched'**
  String get thatSWrapWholeReelWatched;

  /// No description provided for @missionCompleteWholeSeriesLaunched.
  ///
  /// In en, this message translates to:
  /// **'mission complete — whole series launched'**
  String get missionCompleteWholeSeriesLaunched;

  /// No description provided for @thisBedFullyGrown.
  ///
  /// In en, this message translates to:
  /// **'this bed is fully grown'**
  String get thisBedFullyGrown;

  /// No description provided for @thatStretchRoadDone.
  ///
  /// In en, this message translates to:
  /// **'that stretch of road is done'**
  String get thatStretchRoadDone;

  /// No description provided for @thatReelSFullyScreened.
  ///
  /// In en, this message translates to:
  /// **'that reel\'s fully screened'**
  String get thatReelSFullyScreened;

  /// No description provided for @thatStageFullyLaunched.
  ///
  /// In en, this message translates to:
  /// **'that stage is fully launched'**
  String get thatStageFullyLaunched;

  /// No description provided for @theRoadSoFar.
  ///
  /// In en, this message translates to:
  /// **'the road so far'**
  String get theRoadSoFar;

  /// No description provided for @yourCollectedStubs.
  ///
  /// In en, this message translates to:
  /// **'your collected stubs'**
  String get yourCollectedStubs;

  /// No description provided for @yourFlightLog.
  ///
  /// In en, this message translates to:
  /// **'your flight log'**
  String get yourFlightLog;

  /// No description provided for @longestMonthWas.
  ///
  /// In en, this message translates to:
  /// **'longest this month was'**
  String get longestMonthWas;

  /// No description provided for @longestRideMonthWas.
  ///
  /// In en, this message translates to:
  /// **'longest ride this month was'**
  String get longestRideMonthWas;

  /// No description provided for @longestRunMonthWas.
  ///
  /// In en, this message translates to:
  /// **'longest run this month was'**
  String get longestRunMonthWas;

  /// No description provided for @longestRunLaunchesMonthWas.
  ///
  /// In en, this message translates to:
  /// **'longest run of launches this month was'**
  String get longestRunLaunchesMonthWas;

  /// No description provided for @justGettingGardenStarted.
  ///
  /// In en, this message translates to:
  /// **'just getting the garden started'**
  String get justGettingGardenStarted;

  /// No description provided for @justGettingEngineWarmedUp.
  ///
  /// In en, this message translates to:
  /// **'just getting the engine warmed up'**
  String get justGettingEngineWarmedUp;

  /// No description provided for @justGettingReelLoaded.
  ///
  /// In en, this message translates to:
  /// **'just getting the reel loaded'**
  String get justGettingReelLoaded;

  /// No description provided for @justClearingLaunchPad.
  ///
  /// In en, this message translates to:
  /// **'just clearing the launch pad'**
  String get justClearingLaunchPad;

  /// No description provided for @growingSlowly.
  ///
  /// In en, this message translates to:
  /// **', growing slowly'**
  String get growingSlowly;

  /// No description provided for @alwaysUp.
  ///
  /// In en, this message translates to:
  /// **'always up for'**
  String get alwaysUp;

  /// No description provided for @onLongDrive.
  ///
  /// In en, this message translates to:
  /// **'on a long drive'**
  String get onLongDrive;

  /// No description provided for @alwaysDown.
  ///
  /// In en, this message translates to:
  /// **'always down for a'**
  String get alwaysDown;

  /// No description provided for @marathon.
  ///
  /// In en, this message translates to:
  /// **'marathon'**
  String get marathon;

  /// No description provided for @alwaysCleared.
  ///
  /// In en, this message translates to:
  /// **'always cleared for a'**
  String get alwaysCleared;

  /// No description provided for @timeWaterGarden.
  ///
  /// In en, this message translates to:
  /// **'time to water the garden'**
  String get timeWaterGarden;

  /// No description provided for @nextStopWaiting.
  ///
  /// In en, this message translates to:
  /// **'next stop is waiting'**
  String get nextStopWaiting;

  /// No description provided for @tonightSShowingComingUp.
  ///
  /// In en, this message translates to:
  /// **'tonight\'s showing is coming up'**
  String get tonightSShowingComingUp;

  /// No description provided for @tonightSLaunchWindowOpen.
  ///
  /// In en, this message translates to:
  /// **'tonight\'s launch window is open'**
  String get tonightSLaunchWindowOpen;

  /// No description provided for @theseOnlyCountWhatSActually.
  ///
  /// In en, this message translates to:
  /// **'these only count what\'s actually grown here — please log your evenings honestly'**
  String get theseOnlyCountWhatSActually;

  /// No description provided for @theseOnlyCountRoadVeActually.
  ///
  /// In en, this message translates to:
  /// **'these only count the road you\'ve actually driven — please log your evenings honestly'**
  String get theseOnlyCountRoadVeActually;

  /// No description provided for @theseOnlyCountWhatSActually2.
  ///
  /// In en, this message translates to:
  /// **'these only count what\'s actually played on the reel — please log your evenings honestly'**
  String get theseOnlyCountWhatSActually2;

  /// No description provided for @theseOnlyCountWhatSActually3.
  ///
  /// In en, this message translates to:
  /// **'these only count what\'s actually launched here — please log your evenings honestly'**
  String get theseOnlyCountWhatSActually3;

  /// No description provided for @yourGardenLevel.
  ///
  /// In en, this message translates to:
  /// **'your garden is at level'**
  String get yourGardenLevel;

  /// No description provided for @atCinema.
  ///
  /// In en, this message translates to:
  /// **'at the cinema'**
  String get atCinema;

  /// No description provided for @xpGrowsFromWhatActuallyPlant.
  ///
  /// In en, this message translates to:
  /// **'xp grows from what you actually plant here — logged evenings, reviews, rewatches, streaks, and genres explored'**
  String get xpGrowsFromWhatActuallyPlant;

  /// No description provided for @xpComesFromMilesVeActually.
  ///
  /// In en, this message translates to:
  /// **'xp comes from the miles you\'ve actually driven — logged evenings, reviews, rewatches, streaks, and genres explored'**
  String get xpComesFromMilesVeActually;

  /// No description provided for @xpComesFromWhatSActually.
  ///
  /// In en, this message translates to:
  /// **'xp comes from what\'s actually played on the reel — logged evenings, reviews, rewatches, streaks, and genres explored'**
  String get xpComesFromWhatSActually;

  /// No description provided for @xpComesFromWhatVeActually.
  ///
  /// In en, this message translates to:
  /// **'xp comes from what you\'ve actually launched — logged evenings, reviews, rewatches, streaks, and genres explored'**
  String get xpComesFromWhatVeActually;

  /// No description provided for @eveningsPlanted.
  ///
  /// In en, this message translates to:
  /// **'evenings planted'**
  String get eveningsPlanted;

  /// No description provided for @eveningsDriven.
  ///
  /// In en, this message translates to:
  /// **'evenings driven'**
  String get eveningsDriven;

  /// No description provided for @eveningsScreened.
  ///
  /// In en, this message translates to:
  /// **'evenings screened'**
  String get eveningsScreened;

  /// No description provided for @eveningsLaunched.
  ///
  /// In en, this message translates to:
  /// **'evenings launched'**
  String get eveningsLaunched;

  /// No description provided for @notesLeftVine.
  ///
  /// In en, this message translates to:
  /// **'notes left on the vine'**
  String get notesLeftVine;

  /// No description provided for @notesFromRoad.
  ///
  /// In en, this message translates to:
  /// **'notes from the road'**
  String get notesFromRoad;

  /// No description provided for @reviewsWritten.
  ///
  /// In en, this message translates to:
  /// **'reviews written'**
  String get reviewsWritten;

  /// No description provided for @flightLogsWritten.
  ///
  /// In en, this message translates to:
  /// **'flight logs written'**
  String get flightLogsWritten;

  /// No description provided for @replantedFavorite.
  ///
  /// In en, this message translates to:
  /// **'replanted a favorite'**
  String get replantedFavorite;

  /// No description provided for @retracedRoutes.
  ///
  /// In en, this message translates to:
  /// **'retraced routes'**
  String get retracedRoutes;

  /// No description provided for @rewatchesLogged.
  ///
  /// In en, this message translates to:
  /// **'rewatches logged'**
  String get rewatchesLogged;

  /// No description provided for @repeatLaunches.
  ///
  /// In en, this message translates to:
  /// **'repeat launches'**
  String get repeatLaunches;

  /// No description provided for @genresBloom.
  ///
  /// In en, this message translates to:
  /// **'genres in bloom'**
  String get genresBloom;

  /// No description provided for @genresExplored.
  ///
  /// In en, this message translates to:
  /// **'genres explored'**
  String get genresExplored;

  /// No description provided for @genresMarquee.
  ///
  /// In en, this message translates to:
  /// **'genres on the marquee'**
  String get genresMarquee;

  /// No description provided for @genresCharted.
  ///
  /// In en, this message translates to:
  /// **'genres charted'**
  String get genresCharted;

  /// No description provided for @longestGrowingStreak.
  ///
  /// In en, this message translates to:
  /// **'longest growing streak'**
  String get longestGrowingStreak;

  /// No description provided for @longestRunRoad.
  ///
  /// In en, this message translates to:
  /// **'longest run of the road'**
  String get longestRunRoad;

  /// No description provided for @longestRunCinema.
  ///
  /// In en, this message translates to:
  /// **'longest run at the cinema'**
  String get longestRunCinema;

  /// No description provided for @longestLaunchStreak.
  ///
  /// In en, this message translates to:
  /// **'longest launch streak'**
  String get longestLaunchStreak;

  /// No description provided for @text.
  ///
  /// In en, this message translates to:
  /// **'\"'**
  String get text;

  /// No description provided for @n1.
  ///
  /// In en, this message translates to:
  /// **'1'**
  String get n1;

  /// No description provided for @n10.
  ///
  /// In en, this message translates to:
  /// **'10'**
  String get n10;

  /// No description provided for @admitOne.
  ///
  /// In en, this message translates to:
  /// **'ADMIT ONE'**
  String get admitOne;

  /// No description provided for @code12.
  ///
  /// In en, this message translates to:
  /// **'CODE12'**
  String get code12;

  /// No description provided for @departures.
  ///
  /// In en, this message translates to:
  /// **'DEPARTURES'**
  String get departures;

  /// No description provided for @iM.
  ///
  /// In en, this message translates to:
  /// **'I\'m in'**
  String get iM;

  /// No description provided for @nowBoarding.
  ///
  /// In en, this message translates to:
  /// **'NOW BOARDING'**
  String get nowBoarding;

  /// No description provided for @nowShowing.
  ///
  /// In en, this message translates to:
  /// **'NOW SHOWING'**
  String get nowShowing;

  /// No description provided for @noWrittenReviewsTitleYet.
  ///
  /// In en, this message translates to:
  /// **'No written reviews for this title yet'**
  String get noWrittenReviewsTitleYet;

  /// No description provided for @pS.
  ///
  /// In en, this message translates to:
  /// **'P.S.'**
  String get pS;

  /// No description provided for @seenly.
  ///
  /// In en, this message translates to:
  /// **'SEENLY'**
  String get seenly;

  /// No description provided for @teamira.
  ///
  /// In en, this message translates to:
  /// **'TEAMIRA'**
  String get teamira;

  /// No description provided for @vs.
  ///
  /// In en, this message translates to:
  /// **'VS'**
  String get vs;

  /// No description provided for @youtubeTwitchBroughtByLinkKept.
  ///
  /// In en, this message translates to:
  /// **'YouTube and Twitch, brought in by link — kept separate from your '**
  String get youtubeTwitchBroughtByLinkKept;

  /// No description provided for @aCompanionGrows.
  ///
  /// In en, this message translates to:
  /// **'a companion that grows with you'**
  String get aCompanionGrows;

  /// No description provided for @almostThere.
  ///
  /// In en, this message translates to:
  /// **'almost there'**
  String get almostThere;

  /// No description provided for @ago.
  ///
  /// In en, this message translates to:
  /// **'ago'**
  String get ago;

  /// No description provided for @autoUseDeviceRegion.
  ///
  /// In en, this message translates to:
  /// **'auto (use device region)'**
  String get autoUseDeviceRegion;

  /// No description provided for @australia.
  ///
  /// In en, this message translates to:
  /// **'Australia'**
  String get australia;

  /// No description provided for @belarus.
  ///
  /// In en, this message translates to:
  /// **'Belarus'**
  String get belarus;

  /// No description provided for @brazil.
  ///
  /// In en, this message translates to:
  /// **'Brazil'**
  String get brazil;

  /// No description provided for @canada.
  ///
  /// In en, this message translates to:
  /// **'Canada'**
  String get canada;

  /// No description provided for @france.
  ///
  /// In en, this message translates to:
  /// **'France'**
  String get france;

  /// No description provided for @germany.
  ///
  /// In en, this message translates to:
  /// **'Germany'**
  String get germany;

  /// No description provided for @india.
  ///
  /// In en, this message translates to:
  /// **'India'**
  String get india;

  /// No description provided for @italy.
  ///
  /// In en, this message translates to:
  /// **'Italy'**
  String get italy;

  /// No description provided for @japan.
  ///
  /// In en, this message translates to:
  /// **'Japan'**
  String get japan;

  /// No description provided for @kazakhstan.
  ///
  /// In en, this message translates to:
  /// **'Kazakhstan'**
  String get kazakhstan;

  /// No description provided for @southKorea.
  ///
  /// In en, this message translates to:
  /// **'South Korea'**
  String get southKorea;

  /// No description provided for @poland.
  ///
  /// In en, this message translates to:
  /// **'Poland'**
  String get poland;

  /// No description provided for @russia.
  ///
  /// In en, this message translates to:
  /// **'Russia'**
  String get russia;

  /// No description provided for @spain.
  ///
  /// In en, this message translates to:
  /// **'Spain'**
  String get spain;

  /// No description provided for @turkey.
  ///
  /// In en, this message translates to:
  /// **'Turkey'**
  String get turkey;

  /// No description provided for @ukraine.
  ///
  /// In en, this message translates to:
  /// **'Ukraine'**
  String get ukraine;

  /// No description provided for @unitedKingdom.
  ///
  /// In en, this message translates to:
  /// **'United Kingdom'**
  String get unitedKingdom;

  /// No description provided for @unitedStates.
  ///
  /// In en, this message translates to:
  /// **'United States'**
  String get unitedStates;

  /// No description provided for @aCozyEveningDiaryWhatWatch.
  ///
  /// In en, this message translates to:
  /// **'a cozy evening diary for what you watch — not a tracker '**
  String get aCozyEveningDiaryWhatWatch;

  /// No description provided for @aCozyWatchDiary.
  ///
  /// In en, this message translates to:
  /// **'a cozy watch diary'**
  String get aCozyWatchDiary;

  /// No description provided for @aFewFilmsAlreadyLove.
  ///
  /// In en, this message translates to:
  /// **'a few films you already love'**
  String get aFewFilmsAlreadyLove;

  /// No description provided for @aFewStartSearchOwnAbove.
  ///
  /// In en, this message translates to:
  /// **'a few to start with — or search for your own above'**
  String get aFewStartSearchOwnAbove;

  /// No description provided for @aFranchiseMarathonPickedFreshMost.
  ///
  /// In en, this message translates to:
  /// **'a franchise to marathon, picked fresh most days, with a little '**
  String get aFranchiseMarathonPickedFreshMost;

  /// No description provided for @aFriendSInviteCode.
  ///
  /// In en, this message translates to:
  /// **'a friend\'s invite code'**
  String get aFriendSInviteCode;

  /// No description provided for @aLittleGuideEmptyScreensLoading.
  ///
  /// In en, this message translates to:
  /// **'a little guide on empty screens, loading, and milestones'**
  String get aLittleGuideEmptyScreensLoading;

  /// No description provided for @aNoteFutureSelf.
  ///
  /// In en, this message translates to:
  /// **'a note to your future self'**
  String get aNoteFutureSelf;

  /// No description provided for @aPeekWhatSJustAhead.
  ///
  /// In en, this message translates to:
  /// **'a peek at what\'s just ahead'**
  String get aPeekWhatSJustAhead;

  /// No description provided for @aQuickLookAround.
  ///
  /// In en, this message translates to:
  /// **'a quick look around'**
  String get aQuickLookAround;

  /// No description provided for @aQuickNoteAboutOneOptional.
  ///
  /// In en, this message translates to:
  /// **'a quick note about this one (optional)'**
  String get aQuickNoteAboutOneOptional;

  /// No description provided for @aShelfJustTakesMinute.
  ///
  /// In en, this message translates to:
  /// **'a shelf just for you — takes a minute'**
  String get aShelfJustTakesMinute;

  /// No description provided for @aShortlistCountdownWhoeverSGot.
  ///
  /// In en, this message translates to:
  /// **'a shortlist, a countdown, whoever\'s got the most votes when '**
  String get aShortlistCountdownWhoeverSGot;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'account'**
  String get account;

  /// No description provided for @activity.
  ///
  /// In en, this message translates to:
  /// **'activity'**
  String get activity;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'add'**
  String get add;

  /// No description provided for @addFavorite.
  ///
  /// In en, this message translates to:
  /// **'add a favorite'**
  String get addFavorite;

  /// No description provided for @addSource.
  ///
  /// In en, this message translates to:
  /// **'add a source'**
  String get addSource;

  /// No description provided for @addMatchesMyOwnListToo.
  ///
  /// In en, this message translates to:
  /// **'add matches to my own list too?'**
  String get addMatchesMyOwnListToo;

  /// No description provided for @addList.
  ///
  /// In en, this message translates to:
  /// **'add to a list'**
  String get addList;

  /// No description provided for @addCircle.
  ///
  /// In en, this message translates to:
  /// **'add to your circle'**
  String get addCircle;

  /// No description provided for @addWebhookDestination.
  ///
  /// In en, this message translates to:
  /// **'add this as a webhook destination'**
  String get addWebhookDestination;

  /// No description provided for @addedPlanWatch.
  ///
  /// In en, this message translates to:
  /// **'added to plan to watch'**
  String get addedPlanWatch;

  /// No description provided for @addedFindUnderPlanWatch.
  ///
  /// In en, this message translates to:
  /// **'added — find it under plan to watch'**
  String get addedFindUnderPlanWatch;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'all'**
  String get all;

  /// No description provided for @allBoarded.
  ///
  /// In en, this message translates to:
  /// **'all boarded'**
  String get allBoarded;

  /// No description provided for @all2.
  ///
  /// In en, this message translates to:
  /// **'all ›'**
  String get all2;

  /// No description provided for @alreadyDiary.
  ///
  /// In en, this message translates to:
  /// **'already in your diary'**
  String get alreadyDiary;

  /// No description provided for @alreadyKeepingTrackSomewhereElseBring.
  ///
  /// In en, this message translates to:
  /// **'already keeping track somewhere else? bring it over — paste a '**
  String get alreadyKeepingTrackSomewhereElseBring;

  /// No description provided for @alreadyQueuedWatch.
  ///
  /// In en, this message translates to:
  /// **'already queued to watch'**
  String get alreadyQueuedWatch;

  /// No description provided for @alreadyWatching.
  ///
  /// In en, this message translates to:
  /// **'already watching'**
  String get alreadyWatching;

  /// No description provided for @amberSeatsByWindow.
  ///
  /// In en, this message translates to:
  /// **'amber seats are by the window'**
  String get amberSeatsByWindow;

  /// No description provided for @amberSeatsGoodOnes.
  ///
  /// In en, this message translates to:
  /// **'amber seats are the good ones'**
  String get amberSeatsGoodOnes;

  /// No description provided for @anEmptyLotWaiting.
  ///
  /// In en, this message translates to:
  /// **'an empty lot, waiting'**
  String get anEmptyLotWaiting;

  /// No description provided for @anyCityWorld.
  ///
  /// In en, this message translates to:
  /// **'any city in the world'**
  String get anyCityWorld;

  /// No description provided for @anyParticularGenre.
  ///
  /// In en, this message translates to:
  /// **'any particular genre?'**
  String get anyParticularGenre;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'appearance'**
  String get appearance;

  /// No description provided for @visualStyle.
  ///
  /// In en, this message translates to:
  /// **'visual style'**
  String get visualStyle;

  /// No description provided for @aPastelPaperSkinTopLight.
  ///
  /// In en, this message translates to:
  /// **'a pastel paper skin on top of light or dark — same diary either way'**
  String get aPastelPaperSkinTopLight;

  /// No description provided for @standard.
  ///
  /// In en, this message translates to:
  /// **'standard'**
  String get standard;

  /// No description provided for @cozyDiary.
  ///
  /// In en, this message translates to:
  /// **'cozy diary'**
  String get cozyDiary;

  /// No description provided for @askTan.
  ///
  /// In en, this message translates to:
  /// **'ask tanè'**
  String get askTan;

  /// No description provided for @askTanVoteLetDicePick.
  ///
  /// In en, this message translates to:
  /// **'ask tanè, vote, or let a dice pick'**
  String get askTanVoteLetDicePick;

  /// No description provided for @askTeamiraVoteLetDicePick.
  ///
  /// In en, this message translates to:
  /// **'ask teamira, vote, or let a dice pick'**
  String get askTeamiraVoteLetDicePick;

  /// No description provided for @autoTracking.
  ///
  /// In en, this message translates to:
  /// **'auto-tracking'**
  String get autoTracking;

  /// No description provided for @autoTrackingPicksUpFromPlex.
  ///
  /// In en, this message translates to:
  /// **'auto-tracking picks it up from Plex, Jellyfin, Kodi or your '**
  String get autoTrackingPicksUpFromPlex;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'back'**
  String get back;

  /// No description provided for @backCollections.
  ///
  /// In en, this message translates to:
  /// **'back to collections'**
  String get backCollections;

  /// No description provided for @badges.
  ///
  /// In en, this message translates to:
  /// **'badges'**
  String get badges;

  /// No description provided for @warmingUp.
  ///
  /// In en, this message translates to:
  /// **'warming up'**
  String get warmingUp;

  /// No description provided for @movieBuff.
  ///
  /// In en, this message translates to:
  /// **'movie buff'**
  String get movieBuff;

  /// No description provided for @n100Films.
  ///
  /// In en, this message translates to:
  /// **'100 films'**
  String get n100Films;

  /// No description provided for @filmScholar.
  ///
  /// In en, this message translates to:
  /// **'film scholar'**
  String get filmScholar;

  /// No description provided for @comedyConnoisseur.
  ///
  /// In en, this message translates to:
  /// **'comedy connoisseur'**
  String get comedyConnoisseur;

  /// No description provided for @braveEnough.
  ///
  /// In en, this message translates to:
  /// **'brave enough'**
  String get braveEnough;

  /// No description provided for @stillKidHeart.
  ///
  /// In en, this message translates to:
  /// **'still a kid at heart'**
  String get stillKidHeart;

  /// No description provided for @curiousMind.
  ///
  /// In en, this message translates to:
  /// **'curious mind'**
  String get curiousMind;

  /// No description provided for @genreExplorer.
  ///
  /// In en, this message translates to:
  /// **'genre explorer'**
  String get genreExplorer;

  /// No description provided for @firstReview.
  ///
  /// In en, this message translates to:
  /// **'first review'**
  String get firstReview;

  /// No description provided for @secondViewing.
  ///
  /// In en, this message translates to:
  /// **'second viewing'**
  String get secondViewing;

  /// No description provided for @oneGoodWeek.
  ///
  /// In en, this message translates to:
  /// **'one good week'**
  String get oneGoodWeek;

  /// No description provided for @aWholeMonth.
  ///
  /// In en, this message translates to:
  /// **'a whole month'**
  String get aWholeMonth;

  /// No description provided for @tripleDigits.
  ///
  /// In en, this message translates to:
  /// **'triple digits'**
  String get tripleDigits;

  /// No description provided for @unbrokenYear.
  ///
  /// In en, this message translates to:
  /// **'unbroken year'**
  String get unbrokenYear;

  /// No description provided for @oneTripAroundSun.
  ///
  /// In en, this message translates to:
  /// **'one trip around the sun'**
  String get oneTripAroundSun;

  /// No description provided for @level5.
  ///
  /// In en, this message translates to:
  /// **'level 5'**
  String get level5;

  /// No description provided for @level10.
  ///
  /// In en, this message translates to:
  /// **'level 10'**
  String get level10;

  /// No description provided for @level15.
  ///
  /// In en, this message translates to:
  /// **'level 15'**
  String get level15;

  /// No description provided for @level20.
  ///
  /// In en, this message translates to:
  /// **'level 20'**
  String get level20;

  /// No description provided for @level25.
  ///
  /// In en, this message translates to:
  /// **'level 25'**
  String get level25;

  /// No description provided for @level30.
  ///
  /// In en, this message translates to:
  /// **'level 30'**
  String get level30;

  /// No description provided for @loggedVeryFirstFilm.
  ///
  /// In en, this message translates to:
  /// **'logged your very first film'**
  String get loggedVeryFirstFilm;

  /// No description provided for @n10FilmsLogged.
  ///
  /// In en, this message translates to:
  /// **'10 films logged'**
  String get n10FilmsLogged;

  /// No description provided for @n50FilmsLogged.
  ///
  /// In en, this message translates to:
  /// **'50 films logged'**
  String get n50FilmsLogged;

  /// No description provided for @aFullHundred.
  ///
  /// In en, this message translates to:
  /// **'a full hundred'**
  String get aFullHundred;

  /// No description provided for @n250FilmsLogged.
  ///
  /// In en, this message translates to:
  /// **'250 films logged'**
  String get n250FilmsLogged;

  /// No description provided for @n10ComediesLogged.
  ///
  /// In en, this message translates to:
  /// **'10 comedies logged'**
  String get n10ComediesLogged;

  /// No description provided for @n10HorrorTitlesLogged.
  ///
  /// In en, this message translates to:
  /// **'10 horror titles logged'**
  String get n10HorrorTitlesLogged;

  /// No description provided for @n10AnimatedFilmsLogged.
  ///
  /// In en, this message translates to:
  /// **'10 animated films logged'**
  String get n10AnimatedFilmsLogged;

  /// No description provided for @n10DocumentariesLogged.
  ///
  /// In en, this message translates to:
  /// **'10 documentaries logged'**
  String get n10DocumentariesLogged;

  /// No description provided for @watchedAcross8DifferentGenres.
  ///
  /// In en, this message translates to:
  /// **'watched across 8+ different genres'**
  String get watchedAcross8DifferentGenres;

  /// No description provided for @wroteNoteLoggedEvening.
  ///
  /// In en, this message translates to:
  /// **'wrote a note on a logged evening'**
  String get wroteNoteLoggedEvening;

  /// No description provided for @loggedRewatch.
  ///
  /// In en, this message translates to:
  /// **'logged a rewatch'**
  String get loggedRewatch;

  /// No description provided for @a7DayStreak.
  ///
  /// In en, this message translates to:
  /// **'a 7-day streak'**
  String get a7DayStreak;

  /// No description provided for @a30DayStreak.
  ///
  /// In en, this message translates to:
  /// **'a 30-day streak'**
  String get a30DayStreak;

  /// No description provided for @a100DayStreak.
  ///
  /// In en, this message translates to:
  /// **'a 100-day streak'**
  String get a100DayStreak;

  /// No description provided for @a365DayStreak.
  ///
  /// In en, this message translates to:
  /// **'a 365-day streak'**
  String get a365DayStreak;

  /// No description provided for @n365DaysTan.
  ///
  /// In en, this message translates to:
  /// **'365 days on tanè'**
  String get n365DaysTan;

  /// No description provided for @reachedLevel5.
  ///
  /// In en, this message translates to:
  /// **'reached level 5'**
  String get reachedLevel5;

  /// No description provided for @reachedLevel10.
  ///
  /// In en, this message translates to:
  /// **'reached level 10'**
  String get reachedLevel10;

  /// No description provided for @reachedLevel15.
  ///
  /// In en, this message translates to:
  /// **'reached level 15'**
  String get reachedLevel15;

  /// No description provided for @reachedLevel20.
  ///
  /// In en, this message translates to:
  /// **'reached level 20'**
  String get reachedLevel20;

  /// No description provided for @reachedLevel25.
  ///
  /// In en, this message translates to:
  /// **'reached level 25'**
  String get reachedLevel25;

  /// No description provided for @reachedLevel30.
  ///
  /// In en, this message translates to:
  /// **'reached level 30'**
  String get reachedLevel30;

  /// No description provided for @watchedAll.
  ///
  /// In en, this message translates to:
  /// **'watched all'**
  String get watchedAll;

  /// No description provided for @inSaga.
  ///
  /// In en, this message translates to:
  /// **'in the saga'**
  String get inSaga;

  /// No description provided for @achievementUnlocked.
  ///
  /// In en, this message translates to:
  /// **'achievement unlocked'**
  String get achievementUnlocked;

  /// No description provided for @tapContinue.
  ///
  /// In en, this message translates to:
  /// **'tap to continue'**
  String get tapContinue;

  /// No description provided for @whyHave.
  ///
  /// In en, this message translates to:
  /// **'why you have it'**
  String get whyHave;

  /// No description provided for @howEarn.
  ///
  /// In en, this message translates to:
  /// **'how to earn it'**
  String get howEarn;

  /// No description provided for @before1980.
  ///
  /// In en, this message translates to:
  /// **'before 1980'**
  String get before1980;

  /// No description provided for @beforeAnythingElseWhatDidTonight.
  ///
  /// In en, this message translates to:
  /// **'before anything else — what did tonight leave you with?'**
  String get beforeAnythingElseWhatDidTonight;

  /// No description provided for @beforeGoesBackGroundWhatTook.
  ///
  /// In en, this message translates to:
  /// **'before it goes back in the ground — what took root?'**
  String get beforeGoesBackGroundWhatTook;

  /// No description provided for @beforeNextStopWhatMadeRide.
  ///
  /// In en, this message translates to:
  /// **'before the next stop — what made the ride?'**
  String get beforeNextStopWhatMadeRide;

  /// No description provided for @beforeCheckStopWhatDidTonight.
  ///
  /// In en, this message translates to:
  /// **'before you check your stop — what did tonight leave you with?'**
  String get beforeCheckStopWhatDidTonight;

  /// No description provided for @beforeHeadBackInsideWhatDid.
  ///
  /// In en, this message translates to:
  /// **'before you head back inside — what did tonight leave you with?'**
  String get beforeHeadBackInsideWhatDid;

  /// No description provided for @blurSynopsis.
  ///
  /// In en, this message translates to:
  /// **'blur the synopsis'**
  String get blurSynopsis;

  /// No description provided for @blurWrittenReviews.
  ///
  /// In en, this message translates to:
  /// **'blur written reviews'**
  String get blurWrittenReviews;

  /// No description provided for @browserExtension.
  ///
  /// In en, this message translates to:
  /// **'browser extension'**
  String get browserExtension;

  /// No description provided for @canTDecide.
  ///
  /// In en, this message translates to:
  /// **'can\'t decide?'**
  String get canTDecide;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'cancel'**
  String get cancel;

  /// No description provided for @comfortWatchNothingHeavy.
  ///
  /// In en, this message translates to:
  /// **'comfort watch, nothing heavy'**
  String get comfortWatchNothingHeavy;

  /// No description provided for @comingUpTomorrow.
  ///
  /// In en, this message translates to:
  /// **'coming up tomorrow'**
  String get comingUpTomorrow;

  /// No description provided for @cast.
  ///
  /// In en, this message translates to:
  /// **'cast'**
  String get cast;

  /// No description provided for @changeAvatar.
  ///
  /// In en, this message translates to:
  /// **'change avatar'**
  String get changeAvatar;

  /// No description provided for @chooseCity.
  ///
  /// In en, this message translates to:
  /// **'choose a city'**
  String get chooseCity;

  /// No description provided for @choosePlot.
  ///
  /// In en, this message translates to:
  /// **'choose a plot'**
  String get choosePlot;

  /// No description provided for @chooseSpot.
  ///
  /// In en, this message translates to:
  /// **'choose a spot'**
  String get chooseSpot;

  /// No description provided for @chooseCinema.
  ///
  /// In en, this message translates to:
  /// **'choose your cinema'**
  String get chooseCinema;

  /// No description provided for @chooseGarden.
  ///
  /// In en, this message translates to:
  /// **'choose your garden'**
  String get chooseGarden;

  /// No description provided for @chooseLaunchSite.
  ///
  /// In en, this message translates to:
  /// **'choose your launch site'**
  String get chooseLaunchSite;

  /// No description provided for @chooseRoute.
  ///
  /// In en, this message translates to:
  /// **'choose your route'**
  String get chooseRoute;

  /// No description provided for @pickSpot.
  ///
  /// In en, this message translates to:
  /// **'pick a spot'**
  String get pickSpot;

  /// No description provided for @plant.
  ///
  /// In en, this message translates to:
  /// **'plant it at'**
  String get plant;

  /// No description provided for @chooseSeat.
  ///
  /// In en, this message translates to:
  /// **'choose your seat'**
  String get chooseSeat;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'clear'**
  String get clear;

  /// No description provided for @clearLaunch.
  ///
  /// In en, this message translates to:
  /// **'clear for launch'**
  String get clearLaunch;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'close'**
  String get close;

  /// No description provided for @closeDiaryNow.
  ///
  /// In en, this message translates to:
  /// **'close this diary for now?'**
  String get closeDiaryNow;

  /// No description provided for @collapse.
  ///
  /// In en, this message translates to:
  /// **'collapse'**
  String get collapse;

  /// No description provided for @codeCopied.
  ///
  /// In en, this message translates to:
  /// **'code copied'**
  String get codeCopied;

  /// No description provided for @codeWaitingThem.
  ///
  /// In en, this message translates to:
  /// **'code waiting for them'**
  String get codeWaitingThem;

  /// No description provided for @collections.
  ///
  /// In en, this message translates to:
  /// **'collections'**
  String get collections;

  /// No description provided for @collectionsLeadsTheseFromDayOne.
  ///
  /// In en, this message translates to:
  /// **'collections leads with these from day one — change this anytime from its header'**
  String get collectionsLeadsTheseFromDayOne;

  /// No description provided for @connections.
  ///
  /// In en, this message translates to:
  /// **'connections'**
  String get connections;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'continue'**
  String get continueLabel;

  /// No description provided for @continueFrom.
  ///
  /// In en, this message translates to:
  /// **'continue from'**
  String get continueFrom;

  /// No description provided for @couldnTAgreeJustNowTry.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t agree to that just now — try again'**
  String get couldnTAgreeJustNowTry;

  /// No description provided for @couldnTCreateListTryAgain.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t create that list — try again'**
  String get couldnTCreateListTryAgain;

  /// No description provided for @couldnTDeleteListTryAgain.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t delete that list — try again'**
  String get couldnTDeleteListTryAgain;

  /// No description provided for @couldnTDeleteEntryTryAgain.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t delete this entry — try again'**
  String get couldnTDeleteEntryTryAgain;

  /// No description provided for @couldnTFindAnotherPickTry.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t find another pick — try again'**
  String get couldnTFindAnotherPickTry;

  /// No description provided for @couldnTGetCodeJustNow.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t get a code just now — try again'**
  String get couldnTGetCodeJustNow;

  /// No description provided for @couldnTLoadCoViewing.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load co-viewing'**
  String get couldnTLoadCoViewing;

  /// No description provided for @couldnTLoadFavorites.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load favorites'**
  String get couldnTLoadFavorites;

  /// No description provided for @couldnTLoadPoolJustNow.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load that pool just now — try again'**
  String get couldnTLoadPoolJustNow;

  /// No description provided for @couldnTLoadJustNow.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load this just now'**
  String get couldnTLoadJustNow;

  /// No description provided for @couldnTLoadList.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load this list'**
  String get couldnTLoadList;

  /// No description provided for @couldnTLoadProfile.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load this profile'**
  String get couldnTLoadProfile;

  /// No description provided for @couldnTLoadInviteCodeTry.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load your invite code — try again in a bit'**
  String get couldnTLoadInviteCodeTry;

  /// No description provided for @couldnTLoadLevel.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load your level'**
  String get couldnTLoadLevel;

  /// No description provided for @couldnTLoadLists.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load your lists'**
  String get couldnTLoadLists;

  /// No description provided for @couldnTLoadSources.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load your sources'**
  String get couldnTLoadSources;

  /// No description provided for @couldnTMarkWatchedTryAgain.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t mark that watched — try again'**
  String get couldnTMarkWatchedTryAgain;

  /// No description provided for @couldnTDoTryAgain.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t do that — try again'**
  String get couldnTDoTryAgain;

  /// No description provided for @couldnTOpenLinkJustNow.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t open that link just now'**
  String get couldnTOpenLinkJustNow;

  /// No description provided for @couldnTOpenNoAppHandle.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t open that — no app to handle it'**
  String get couldnTOpenNoAppHandle;

  /// No description provided for @couldnTProposeJustNowTry.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t propose that just now — try again'**
  String get couldnTProposeJustNowTry;

  /// No description provided for @couldnTReachCatalogTonightS.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t reach the catalog for tonight\'s pick — the rest of your diary loaded fine'**
  String get couldnTReachCatalogTonightS;

  /// No description provided for @couldnTRemoveTryAgain.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t remove that — try again'**
  String get couldnTRemoveTryAgain;

  /// No description provided for @couldnTRotateTokenJustNow.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t rotate the token just now'**
  String get couldnTRotateTokenJustNow;

  /// No description provided for @couldnTSaveAvatar.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t save avatar'**
  String get couldnTSaveAvatar;

  /// No description provided for @couldnTSaveName.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t save name'**
  String get couldnTSaveName;

  /// No description provided for @couldnTSaveStatus.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t save status'**
  String get couldnTSaveStatus;

  /// No description provided for @couldnTSaveJustNowTry.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t save that just now — try again'**
  String get couldnTSaveJustNowTry;

  /// No description provided for @couldnTSaveThoseChangesTry.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t save those changes — try again'**
  String get couldnTSaveThoseChangesTry;

  /// No description provided for @couldnTSendInviteTryAgain.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t send that invite — try again'**
  String get couldnTSendInviteTryAgain;

  /// No description provided for @couldnTSendJustNowTry.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t send that just now — try again'**
  String get couldnTSendJustNowTry;

  /// No description provided for @couldnTShareTryAgain.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t share that — try again'**
  String get couldnTShareTryAgain;

  /// No description provided for @couldnTUnlinkJustNowTry.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t unlink just now — try again'**
  String get couldnTUnlinkJustNowTry;

  /// No description provided for @couldnTUpdateListTryAgain.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t update that list — try again'**
  String get couldnTUpdateListTryAgain;

  /// No description provided for @couldnTAddJustNowTry.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t add that just now — try again'**
  String get couldnTAddJustNowTry;

  /// No description provided for @couldnTLoadDiary.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load the diary'**
  String get couldnTLoadDiary;

  /// No description provided for @couldnTLoadBadges.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load your badges'**
  String get couldnTLoadBadges;

  /// No description provided for @couldnTLoadHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load your history for this title'**
  String get couldnTLoadHistoryTitle;

  /// No description provided for @couldnTLoadProfile2.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load your profile'**
  String get couldnTLoadProfile2;

  /// No description provided for @couldnTLoadTapTryAgain.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load — tap to try again'**
  String get couldnTLoadTapTryAgain;

  /// No description provided for @couldnTReachCollections.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t reach the collections'**
  String get couldnTReachCollections;

  /// No description provided for @couldnTReachDiaryJustNow.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t reach the diary just now'**
  String get couldnTReachDiaryJustNow;

  /// No description provided for @cozyRainyDayPicks.
  ///
  /// In en, this message translates to:
  /// **'cozy rainy-day picks…'**
  String get cozyRainyDayPicks;

  /// No description provided for @darkModeEarlyNowJustChanges.
  ///
  /// In en, this message translates to:
  /// **'dark mode is early — for now it just changes the co-viewing bunnies'**
  String get darkModeEarlyNowJustChanges;

  /// No description provided for @decideTogetherOneCardTime.
  ///
  /// In en, this message translates to:
  /// **'decide together, one card at a time'**
  String get decideTogetherOneCardTime;

  /// No description provided for @depart.
  ///
  /// In en, this message translates to:
  /// **'depart'**
  String get depart;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'delete'**
  String get delete;

  /// No description provided for @deleteEvening.
  ///
  /// In en, this message translates to:
  /// **'delete this evening'**
  String get deleteEvening;

  /// No description provided for @deleteEvening2.
  ///
  /// In en, this message translates to:
  /// **'delete this evening?'**
  String get deleteEvening2;

  /// No description provided for @describeMoodGenreLikeTitle.
  ///
  /// In en, this message translates to:
  /// **'describe a mood, a genre, \"like [title]\"…'**
  String get describeMoodGenreLikeTitle;

  /// No description provided for @diary.
  ///
  /// In en, this message translates to:
  /// **'diary'**
  String get diary;

  /// No description provided for @diary2.
  ///
  /// In en, this message translates to:
  /// **'diary ›'**
  String get diary2;

  /// No description provided for @doesLookRight.
  ///
  /// In en, this message translates to:
  /// **'does this look right?'**
  String get doesLookRight;

  /// No description provided for @donTWantSeatsTicketsAny.
  ///
  /// In en, this message translates to:
  /// **'don\'t want the seats, the tickets, any of it?'**
  String get donTWantSeatsTicketsAny;

  /// No description provided for @dragSearchDarkSeat.
  ///
  /// In en, this message translates to:
  /// **'drag to search the dark for your seat'**
  String get dragSearchDarkSeat;

  /// No description provided for @dragTearSHowBegin.
  ///
  /// In en, this message translates to:
  /// **'drag to tear it — that\'s how you begin'**
  String get dragTearSHowBegin;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'edit'**
  String get edit;

  /// No description provided for @easyBackgroundWhileICook.
  ///
  /// In en, this message translates to:
  /// **'easy background while I cook'**
  String get easyBackgroundWhileICook;

  /// No description provided for @editTapAnotherLineWePicked.
  ///
  /// In en, this message translates to:
  /// **'edit it, or tap another line we picked up below'**
  String get editTapAnotherLineWePicked;

  /// No description provided for @editEvening.
  ///
  /// In en, this message translates to:
  /// **'edit this evening'**
  String get editEvening;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'edit profile'**
  String get editProfile;

  /// No description provided for @enablePlaybackStopItemMarkedPlayed.
  ///
  /// In en, this message translates to:
  /// **'enable \"Playback Stop\" and \"Item Marked Played\"'**
  String get enablePlaybackStopItemMarkedPlayed;

  /// No description provided for @emptyNowAddTitlesHereFrom.
  ///
  /// In en, this message translates to:
  /// **'empty for now — add titles here from any title\'s page'**
  String get emptyNowAddTitlesHereFrom;

  /// No description provided for @endSession.
  ///
  /// In en, this message translates to:
  /// **'end session'**
  String get endSession;

  /// No description provided for @eveningsLogged.
  ///
  /// In en, this message translates to:
  /// **'evenings logged'**
  String get eveningsLogged;

  /// No description provided for @everyUrlVeAlreadyPastedInto.
  ///
  /// In en, this message translates to:
  /// **'every URL you\'ve already pasted into Plex, Jellyfin, Kodi, or the '**
  String get everyUrlVeAlreadyPastedInto;

  /// No description provided for @everyWayTitleEndsUpPlanned.
  ///
  /// In en, this message translates to:
  /// **'every way a title ends up planned, and what it takes to get there'**
  String get everyWayTitleEndsUpPlanned;

  /// No description provided for @everyoneReFriendsAlreadyHereAdd.
  ///
  /// In en, this message translates to:
  /// **'everyone you\'re friends with is already here — add more '**
  String get everyoneReFriendsAlreadyHereAdd;

  /// No description provided for @everythingWeReadOffTicket.
  ///
  /// In en, this message translates to:
  /// **'everything we read off the ticket'**
  String get everythingWeReadOffTicket;

  /// No description provided for @everythingVeLoggedStaysRightWhere.
  ///
  /// In en, this message translates to:
  /// **'everything you\'ve logged stays right where it is — you\'ll pick up from here next time'**
  String get everythingVeLoggedStaysRightWhere;

  /// No description provided for @favorite.
  ///
  /// In en, this message translates to:
  /// **'favorite'**
  String get favorite;

  /// No description provided for @favoritesTonight.
  ///
  /// In en, this message translates to:
  /// **'favorites tonight'**
  String get favoritesTonight;

  /// No description provided for @filmography.
  ///
  /// In en, this message translates to:
  /// **'filmography'**
  String get filmography;

  /// No description provided for @firstWatch.
  ///
  /// In en, this message translates to:
  /// **'first watch'**
  String get firstWatch;

  /// No description provided for @findBlankPage.
  ///
  /// In en, this message translates to:
  /// **'find a blank page'**
  String get findBlankPage;

  /// No description provided for @findMatches.
  ///
  /// In en, this message translates to:
  /// **'find matches'**
  String get findMatches;

  /// No description provided for @findSomeoneByUsername.
  ///
  /// In en, this message translates to:
  /// **'find someone by username'**
  String get findSomeoneByUsername;

  /// No description provided for @findSeat.
  ///
  /// In en, this message translates to:
  /// **'find your seat'**
  String get findSeat;

  /// No description provided for @forTonight.
  ///
  /// In en, this message translates to:
  /// **'for tonight'**
  String get forTonight;

  /// No description provided for @fastPacedKeepsMeHooked.
  ///
  /// In en, this message translates to:
  /// **'fast-paced, keeps me hooked'**
  String get fastPacedKeepsMeHooked;

  /// No description provided for @findingNearbyRoutes.
  ///
  /// In en, this message translates to:
  /// **'finding nearby routes…'**
  String get findingNearbyRoutes;

  /// No description provided for @findingWay.
  ///
  /// In en, this message translates to:
  /// **'finding the way…'**
  String get findingWay;

  /// No description provided for @formerlySeenlySameDiaryNewName.
  ///
  /// In en, this message translates to:
  /// **'formerly seenly — same diary, new name'**
  String get formerlySeenlySameDiaryNewName;

  /// No description provided for @franchisesBestListsPickedByUs.
  ///
  /// In en, this message translates to:
  /// **'franchises, best-of lists — picked by us'**
  String get franchisesBestListsPickedByUs;

  /// No description provided for @friends.
  ///
  /// In en, this message translates to:
  /// **'friends'**
  String get friends;

  /// No description provided for @friendsActivity.
  ///
  /// In en, this message translates to:
  /// **'friends activity'**
  String get friendsActivity;

  /// No description provided for @fullManifest.
  ///
  /// In en, this message translates to:
  /// **'full manifest'**
  String get fullManifest;

  /// No description provided for @gatheredByEditorsTonight.
  ///
  /// In en, this message translates to:
  /// **'gathered by the editors for tonight'**
  String get gatheredByEditorsTonight;

  /// No description provided for @getCode.
  ///
  /// In en, this message translates to:
  /// **'get a code'**
  String get getCode;

  /// No description provided for @goldenMoundsCatchMostSun.
  ///
  /// In en, this message translates to:
  /// **'golden mounds catch the most sun'**
  String get goldenMoundsCatchMostSun;

  /// No description provided for @goodAfternoon.
  ///
  /// In en, this message translates to:
  /// **'good afternoon'**
  String get goodAfternoon;

  /// No description provided for @goodEvening.
  ///
  /// In en, this message translates to:
  /// **'good evening'**
  String get goodEvening;

  /// No description provided for @goodMorning.
  ///
  /// In en, this message translates to:
  /// **'good morning'**
  String get goodMorning;

  /// No description provided for @gotCodeFromThemInstead.
  ///
  /// In en, this message translates to:
  /// **'got a code from them instead?'**
  String get gotCodeFromThemInstead;

  /// No description provided for @gotCode.
  ///
  /// In en, this message translates to:
  /// **'got a code?'**
  String get gotCode;

  /// No description provided for @gotTicketStubFromTonight.
  ///
  /// In en, this message translates to:
  /// **'got a ticket stub from tonight?'**
  String get gotTicketStubFromTonight;

  /// No description provided for @groupWhateverLikeTogetherMoodMarathon.
  ///
  /// In en, this message translates to:
  /// **'group whatever you like together — a mood, a marathon, favorites you keep coming back to'**
  String get groupWhateverLikeTogetherMoodMarathon;

  /// No description provided for @haveCodeAlready.
  ///
  /// In en, this message translates to:
  /// **'have a code already?'**
  String get haveCodeAlready;

  /// No description provided for @haveCodeAlreadyJoinInstead.
  ///
  /// In en, this message translates to:
  /// **'have a code already? join instead'**
  String get haveCodeAlreadyJoinInstead;

  /// No description provided for @haveCodeInstead.
  ///
  /// In en, this message translates to:
  /// **'have a code instead?'**
  String get haveCodeInstead;

  /// No description provided for @haveInviteCode.
  ///
  /// In en, this message translates to:
  /// **'have an invite code?'**
  String get haveInviteCode;

  /// No description provided for @hereSStartingPointChangeSend.
  ///
  /// In en, this message translates to:
  /// **'here\'s a starting point — change it, or send it as is'**
  String get hereSStartingPointChangeSend;

  /// No description provided for @hereSShape.
  ///
  /// In en, this message translates to:
  /// **'here\'s the shape of it'**
  String get hereSShape;

  /// No description provided for @howSwiping.
  ///
  /// In en, this message translates to:
  /// **'how are you swiping?'**
  String get howSwiping;

  /// No description provided for @howCoViewingWorks.
  ///
  /// In en, this message translates to:
  /// **'how co-viewing works'**
  String get howCoViewingWorks;

  /// No description provided for @howFarWe.
  ///
  /// In en, this message translates to:
  /// **'how far in are we?'**
  String get howFarWe;

  /// No description provided for @howFelt.
  ///
  /// In en, this message translates to:
  /// **'how it felt'**
  String get howFelt;

  /// No description provided for @howShouldLoggingFeel.
  ///
  /// In en, this message translates to:
  /// **'how should logging feel?'**
  String get howShouldLoggingFeel;

  /// No description provided for @howShouldWeDecide.
  ///
  /// In en, this message translates to:
  /// **'how should we decide?'**
  String get howShouldWeDecide;

  /// No description provided for @howShouldDecide.
  ///
  /// In en, this message translates to:
  /// **'how should you decide?'**
  String get howShouldDecide;

  /// No description provided for @howRouteMapLooks.
  ///
  /// In en, this message translates to:
  /// **'how the route map looks'**
  String get howRouteMapLooks;

  /// No description provided for @howWorks.
  ///
  /// In en, this message translates to:
  /// **'how this works'**
  String get howWorks;

  /// No description provided for @httpsYoutubeComPlaylistListHttps.
  ///
  /// In en, this message translates to:
  /// **'https://youtube.com/playlist?list=…\nor https://twitch.tv/…'**
  String get httpsYoutubeComPlaylistListHttps;

  /// No description provided for @iMBackRate.
  ///
  /// In en, this message translates to:
  /// **'i\'m back — rate it'**
  String get iMBackRate;

  /// No description provided for @ifTheyReNearbyLetThem.
  ///
  /// In en, this message translates to:
  /// **'if they\'re nearby, let them scan it'**
  String get ifTheyReNearbyLetThem;

  /// No description provided for @ifLiked.
  ///
  /// In en, this message translates to:
  /// **'if you liked this'**
  String get ifLiked;

  /// No description provided for @importFrom.
  ///
  /// In en, this message translates to:
  /// **'import from'**
  String get importFrom;

  /// No description provided for @importHistory.
  ///
  /// In en, this message translates to:
  /// **'import your history'**
  String get importHistory;

  /// No description provided for @installOfficialWebhookPlugin.
  ///
  /// In en, this message translates to:
  /// **'install the official \"Webhook\" plugin'**
  String get installOfficialWebhookPlugin;

  /// No description provided for @installTanScrobblerAddonSeeIntegrations.
  ///
  /// In en, this message translates to:
  /// **'install the tanè Scrobbler addon (see integrations/kodi in the project)'**
  String get installTanScrobblerAddonSeeIntegrations;

  /// No description provided for @intoDiary.
  ///
  /// In en, this message translates to:
  /// **'into the diary'**
  String get intoDiary;

  /// No description provided for @inviteFriends.
  ///
  /// In en, this message translates to:
  /// **'invite friends'**
  String get inviteFriends;

  /// No description provided for @inviteFriendsSeeTheirActivityHere.
  ///
  /// In en, this message translates to:
  /// **'invite friends to see their activity here'**
  String get inviteFriendsSeeTheirActivityHere;

  /// No description provided for @inviteFriendGetFreePremium.
  ///
  /// In en, this message translates to:
  /// **'invite a friend — get free premium'**
  String get inviteFriendGetFreePremium;

  /// No description provided for @inviteFriendBothGetPremium.
  ///
  /// In en, this message translates to:
  /// **'invite a friend — you both get premium'**
  String get inviteFriendBothGetPremium;

  /// No description provided for @eachFriendWhoSticksAroundGets.
  ///
  /// In en, this message translates to:
  /// **'each friend who sticks around gets'**
  String get eachFriendWhoSticksAroundGets;

  /// No description provided for @daysPremiumToo.
  ///
  /// In en, this message translates to:
  /// **'days of premium too'**
  String get daysPremiumToo;

  /// No description provided for @inviteFriendSeeThemHere.
  ///
  /// In en, this message translates to:
  /// **'invite a friend to see them here'**
  String get inviteFriendSeeThemHere;

  /// No description provided for @myInvites.
  ///
  /// In en, this message translates to:
  /// **'my invites'**
  String get myInvites;

  /// No description provided for @invited.
  ///
  /// In en, this message translates to:
  /// **'invited'**
  String get invited;

  /// No description provided for @couldnTLoadInvitesTryAgain.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load your invites — try again in a bit'**
  String get couldnTLoadInvitesTryAgain;

  /// No description provided for @confirmed.
  ///
  /// In en, this message translates to:
  /// **'confirmed'**
  String get confirmed;

  /// No description provided for @nextReward.
  ///
  /// In en, this message translates to:
  /// **'next reward'**
  String get nextReward;

  /// No description provided for @daysPremium.
  ///
  /// In en, this message translates to:
  /// **'days of premium'**
  String get daysPremium;

  /// No description provided for @everyRewardEarnedSoFar.
  ///
  /// In en, this message translates to:
  /// **'every reward earned so far'**
  String get everyRewardEarnedSoFar;

  /// No description provided for @stillConfirming.
  ///
  /// In en, this message translates to:
  /// **'still confirming'**
  String get stillConfirming;

  /// No description provided for @yourPromoCode.
  ///
  /// In en, this message translates to:
  /// **'your promo code'**
  String get yourPromoCode;

  /// No description provided for @givesWhoeverUses.
  ///
  /// In en, this message translates to:
  /// **'gives whoever uses it'**
  String get givesWhoeverUses;

  /// No description provided for @offTheirFirstPremiumPurchase.
  ///
  /// In en, this message translates to:
  /// **'off their first premium purchase'**
  String get offTheirFirstPremiumPurchase;

  /// No description provided for @shareCode.
  ///
  /// In en, this message translates to:
  /// **'share code'**
  String get shareCode;

  /// No description provided for @rewardEarned.
  ///
  /// In en, this message translates to:
  /// **'reward earned'**
  String get rewardEarned;

  /// No description provided for @notCounted.
  ///
  /// In en, this message translates to:
  /// **'not counted'**
  String get notCounted;

  /// No description provided for @confirming.
  ///
  /// In en, this message translates to:
  /// **'confirming'**
  String get confirming;

  /// No description provided for @needs.
  ///
  /// In en, this message translates to:
  /// **'needs'**
  String get needs;

  /// No description provided for @daysRow.
  ///
  /// In en, this message translates to:
  /// **'days in a row'**
  String get daysRow;

  /// No description provided for @entries.
  ///
  /// In en, this message translates to:
  /// **'entries'**
  String get entries;

  /// No description provided for @countsNoEarlierThan.
  ///
  /// In en, this message translates to:
  /// **'counts no earlier than'**
  String get countsNoEarlierThan;

  /// No description provided for @havePromoCode.
  ///
  /// In en, this message translates to:
  /// **'have a promo code?'**
  String get havePromoCode;

  /// No description provided for @promoCode.
  ///
  /// In en, this message translates to:
  /// **'promo code'**
  String get promoCode;

  /// No description provided for @eGAb4qpccl.
  ///
  /// In en, this message translates to:
  /// **'e.g. AB4QPCCL'**
  String get eGAb4qpccl;

  /// No description provided for @promoCodeApplied.
  ///
  /// In en, this message translates to:
  /// **'promo code applied'**
  String get promoCodeApplied;

  /// No description provided for @yourStandingDiscountApplied.
  ///
  /// In en, this message translates to:
  /// **'your standing discount applied'**
  String get yourStandingDiscountApplied;

  /// No description provided for @justHandfulNotEverythingVeEver.
  ///
  /// In en, this message translates to:
  /// **'just a handful — not everything you\'ve ever watched, that part '**
  String get justHandfulNotEverythingVeEver;

  /// No description provided for @keepGoing.
  ///
  /// In en, this message translates to:
  /// **'keep going'**
  String get keepGoing;

  /// No description provided for @keep.
  ///
  /// In en, this message translates to:
  /// **'keep it'**
  String get keep;

  /// No description provided for @keepOneRoad.
  ///
  /// In en, this message translates to:
  /// **'keep this one for the road'**
  String get keepOneRoad;

  /// No description provided for @keepOneGarden.
  ///
  /// In en, this message translates to:
  /// **'keep this one in the garden'**
  String get keepOneGarden;

  /// No description provided for @keepOneLog.
  ///
  /// In en, this message translates to:
  /// **'keep this one in the log'**
  String get keepOneLog;

  /// No description provided for @keepStubFavorites.
  ///
  /// In en, this message translates to:
  /// **'keep this stub in your favorites'**
  String get keepStubFavorites;

  /// No description provided for @keepEveningGoingWhatComesNext.
  ///
  /// In en, this message translates to:
  /// **'keep the evening going with what comes next'**
  String get keepEveningGoingWhatComesNext;

  /// No description provided for @keptPrivate.
  ///
  /// In en, this message translates to:
  /// **'kept private'**
  String get keptPrivate;

  /// No description provided for @kodi.
  ///
  /// In en, this message translates to:
  /// **'kodi'**
  String get kodi;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'language'**
  String get language;

  /// No description provided for @leaveAloneAnythingPickFewNarrow.
  ///
  /// In en, this message translates to:
  /// **'leave this alone for anything — pick a few to narrow the deck '**
  String get leaveAloneAnythingPickFewNarrow;

  /// No description provided for @leaveWithoutFinishing.
  ///
  /// In en, this message translates to:
  /// **'leave without finishing?'**
  String get leaveWithoutFinishing;

  /// No description provided for @leaveCoViewingCircle.
  ///
  /// In en, this message translates to:
  /// **'leave this co-viewing circle?'**
  String get leaveCoViewingCircle;

  /// No description provided for @letGo.
  ///
  /// In en, this message translates to:
  /// **'let it go'**
  String get letGo;

  /// No description provided for @likeTitleILoved.
  ///
  /// In en, this message translates to:
  /// **'like [a title I loved]'**
  String get likeTitleILoved;

  /// No description provided for @letPlanGo.
  ///
  /// In en, this message translates to:
  /// **'let this plan go?'**
  String get letPlanGo;

  /// No description provided for @letSFigureOut.
  ///
  /// In en, this message translates to:
  /// **'let\'s figure it out'**
  String get letSFigureOut;

  /// No description provided for @levelPath.
  ///
  /// In en, this message translates to:
  /// **'level path'**
  String get levelPath;

  /// No description provided for @lightsDown.
  ///
  /// In en, this message translates to:
  /// **'lights down'**
  String get lightsDown;

  /// No description provided for @linkPartner.
  ///
  /// In en, this message translates to:
  /// **'link a partner'**
  String get linkPartner;

  /// No description provided for @linkUp.
  ///
  /// In en, this message translates to:
  /// **'link up'**
  String get linkUp;

  /// No description provided for @listName.
  ///
  /// In en, this message translates to:
  /// **'list name…'**
  String get listName;

  /// No description provided for @logEveningPlantFirstFlower.
  ///
  /// In en, this message translates to:
  /// **'log an evening to plant the first flower'**
  String get logEveningPlantFirstFlower;

  /// No description provided for @loadExtensionSeeIntegrationsBrowserExtension.
  ///
  /// In en, this message translates to:
  /// **'load the extension (see integrations/browser-extension in the project)'**
  String get loadExtensionSeeIntegrationsBrowserExtension;

  /// No description provided for @logEveningsWithoutOpeningApp.
  ///
  /// In en, this message translates to:
  /// **'log evenings without opening the app'**
  String get logEveningsWithoutOpeningApp;

  /// No description provided for @logNow.
  ///
  /// In en, this message translates to:
  /// **'log it now →'**
  String get logNow;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'log out'**
  String get logOut;

  /// No description provided for @logging.
  ///
  /// In en, this message translates to:
  /// **'logging'**
  String get logging;

  /// No description provided for @mapStyle.
  ///
  /// In en, this message translates to:
  /// **'map style'**
  String get mapStyle;

  /// No description provided for @mediaServers.
  ///
  /// In en, this message translates to:
  /// **'media servers'**
  String get mediaServers;

  /// No description provided for @mixTheseIntoMainList.
  ///
  /// In en, this message translates to:
  /// **'mix these into your main list?'**
  String get mixTheseIntoMainList;

  /// No description provided for @mixSourcesIntoMainList.
  ///
  /// In en, this message translates to:
  /// **'mix your sources into the main list?'**
  String get mixSourcesIntoMainList;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'more'**
  String get more;

  /// No description provided for @moreBunniesJoinCollectionNewLevels.
  ///
  /// In en, this message translates to:
  /// **'more bunnies join the collection as new levels arrive.'**
  String get moreBunniesJoinCollectionNewLevels;

  /// No description provided for @needLeastTwoTitlesVoteBetween.
  ///
  /// In en, this message translates to:
  /// **'need at least two titles to vote between — try loosening the filters'**
  String get needLeastTwoTitlesVoteBetween;

  /// No description provided for @neverMind.
  ///
  /// In en, this message translates to:
  /// **'never mind'**
  String get neverMind;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'next'**
  String get next;

  /// No description provided for @nextFeature.
  ///
  /// In en, this message translates to:
  /// **'next feature'**
  String get nextFeature;

  /// No description provided for @newEntry.
  ///
  /// In en, this message translates to:
  /// **'new entry'**
  String get newEntry;

  /// No description provided for @newHereStartDiary.
  ///
  /// In en, this message translates to:
  /// **'new here? start a diary'**
  String get newHereStartDiary;

  /// No description provided for @newList.
  ///
  /// In en, this message translates to:
  /// **'new list'**
  String get newList;

  /// No description provided for @noAccountMatchNoProblemBox.
  ///
  /// In en, this message translates to:
  /// **'no account to match? no problem — the box below is exactly '**
  String get noAccountMatchNoProblemBox;

  /// No description provided for @noEveningsLoggedYetTitle.
  ///
  /// In en, this message translates to:
  /// **'no evenings logged yet for this title'**
  String get noEveningsLoggedYetTitle;

  /// No description provided for @noEveningsRoadYet.
  ///
  /// In en, this message translates to:
  /// **'no evenings on the road yet'**
  String get noEveningsRoadYet;

  /// No description provided for @noGenresLoggedPoolYet.
  ///
  /// In en, this message translates to:
  /// **'no genres logged for this pool yet'**
  String get noGenresLoggedPoolYet;

  /// No description provided for @noListsYet.
  ///
  /// In en, this message translates to:
  /// **'no lists yet'**
  String get noListsYet;

  /// No description provided for @noMatchWillSkipped.
  ///
  /// In en, this message translates to:
  /// **'no match — will be skipped'**
  String get noMatchWillSkipped;

  /// No description provided for @noMatches.
  ///
  /// In en, this message translates to:
  /// **'no matches'**
  String get noMatches;

  /// No description provided for @noOneTanHasUsername.
  ///
  /// In en, this message translates to:
  /// **'no one on tanè has that username'**
  String get noOneTanHasUsername;

  /// No description provided for @noPartnerLinkedYetInviteOne.
  ///
  /// In en, this message translates to:
  /// **'no partner linked yet — invite one to plan evenings together'**
  String get noPartnerLinkedYetInviteOne;

  /// No description provided for @noRouteYet.
  ///
  /// In en, this message translates to:
  /// **'no route yet'**
  String get noRouteYet;

  /// No description provided for @noSeatsNoTicketsNoAnimations.
  ///
  /// In en, this message translates to:
  /// **'no seats, no tickets, no animations — every log just happens instantly'**
  String get noSeatsNoTicketsNoAnimations;

  /// No description provided for @noStreaksKeepNothingFallBehind.
  ///
  /// In en, this message translates to:
  /// **'no streaks to keep and nothing to fall behind on — log an '**
  String get noStreaksKeepNothingFallBehind;

  /// No description provided for @noYearsLoggedPoolYet.
  ///
  /// In en, this message translates to:
  /// **'no years logged for this pool yet'**
  String get noYearsLoggedPoolYet;

  /// No description provided for @noneWatchedYetFirstOneS.
  ///
  /// In en, this message translates to:
  /// **'none watched yet — first one\'s a click away'**
  String get noneWatchedYetFirstOneS;

  /// No description provided for @nobodyVotedBeforeTimeRanOut.
  ///
  /// In en, this message translates to:
  /// **'nobody voted before time ran out.'**
  String get nobodyVotedBeforeTimeRanOut;

  /// No description provided for @normallyLogSomethingByOpeningApp.
  ///
  /// In en, this message translates to:
  /// **'normally you log something by opening the app yourself. '**
  String get normallyLogSomethingByOpeningApp;

  /// No description provided for @notLoggedYetSaveEveningBelow.
  ///
  /// In en, this message translates to:
  /// **'not logged yet — save an evening below'**
  String get notLoggedYetSaveEveningBelow;

  /// No description provided for @notEarnedYet.
  ///
  /// In en, this message translates to:
  /// **'not earned yet'**
  String get notEarnedYet;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'not now'**
  String get notNow;

  /// No description provided for @notTanYetSendThemCode.
  ///
  /// In en, this message translates to:
  /// **'not on tanè yet? send them your code'**
  String get notTanYetSendThemCode;

  /// No description provided for @notSureWhatSearch.
  ///
  /// In en, this message translates to:
  /// **'not sure what to search for?'**
  String get notSureWhatSearch;

  /// No description provided for @notSureWhatWatchPlay.
  ///
  /// In en, this message translates to:
  /// **'not sure what to watch or play?'**
  String get notSureWhatWatchPlay;

  /// No description provided for @notYetRated.
  ///
  /// In en, this message translates to:
  /// **'not yet rated'**
  String get notYetRated;

  /// No description provided for @nothingFound.
  ///
  /// In en, this message translates to:
  /// **'nothing found'**
  String get nothingFound;

  /// No description provided for @nothingMatched.
  ///
  /// In en, this message translates to:
  /// **'nothing matched'**
  String get nothingMatched;

  /// No description provided for @nothingFromFriendsYetOnceThey.
  ///
  /// In en, this message translates to:
  /// **'nothing from friends yet — once they log something, it\'ll show up here'**
  String get nothingFromFriendsYetOnceThey;

  /// No description provided for @nothingHereYet.
  ///
  /// In en, this message translates to:
  /// **'nothing here yet'**
  String get nothingHereYet;

  /// No description provided for @nothingHereYetPasteYoutubeTwitch.
  ///
  /// In en, this message translates to:
  /// **'nothing here yet — paste a YouTube or Twitch link to bring '**
  String get nothingHereYetPasteYoutubeTwitch;

  /// No description provided for @nothingProgressStartWatchingSomethingSee.
  ///
  /// In en, this message translates to:
  /// **'nothing in progress — start watching something to see it here'**
  String get nothingProgressStartWatchingSomethingSee;

  /// No description provided for @nothingLoggedYetFindSomethingTuck.
  ///
  /// In en, this message translates to:
  /// **'nothing logged yet — find something and tuck it in'**
  String get nothingLoggedYetFindSomethingTuck;

  /// No description provided for @nothingMatchedTryDescribingDifferently.
  ///
  /// In en, this message translates to:
  /// **'nothing matched that — try describing it differently'**
  String get nothingMatchedTryDescribingDifferently;

  /// No description provided for @nothingMatchedTryDifferentWords.
  ///
  /// In en, this message translates to:
  /// **'nothing matched that — try different words'**
  String get nothingMatchedTryDifferentWords;

  /// No description provided for @nothingMatchedThoseFiltersGoBack.
  ///
  /// In en, this message translates to:
  /// **'nothing matched those filters — go back and loosen them up'**
  String get nothingMatchedThoseFiltersGoBack;

  /// No description provided for @nothingMatchesPoolTryLooseningUp.
  ///
  /// In en, this message translates to:
  /// **'nothing matches that in this pool — try loosening it up'**
  String get nothingMatchesPoolTryLooseningUp;

  /// No description provided for @nothingProgrammeYet.
  ///
  /// In en, this message translates to:
  /// **'nothing on the programme yet'**
  String get nothingProgrammeYet;

  /// No description provided for @nothingPersonRightNow.
  ///
  /// In en, this message translates to:
  /// **'nothing on this person right now'**
  String get nothingPersonRightNow;

  /// No description provided for @nothingPlanWatchShelfYetSearch.
  ///
  /// In en, this message translates to:
  /// **'nothing on your plan-to-watch shelf yet — search for a title '**
  String get nothingPlanWatchShelfYetSearch;

  /// No description provided for @nothingPinnedYetHeartFilmS.
  ///
  /// In en, this message translates to:
  /// **'nothing pinned yet — the heart on a film\'s page adds it here'**
  String get nothingPinnedYetHeartFilmS;

  /// No description provided for @nothingPinnedYetTapAddHeart.
  ///
  /// In en, this message translates to:
  /// **'nothing pinned yet — tap add, or the heart on a film\'s page'**
  String get nothingPinnedYetTapAddHeart;

  /// No description provided for @nothingPickedYetFineTooHeart.
  ///
  /// In en, this message translates to:
  /// **'nothing picked yet is fine too — the heart on any title does the same thing later'**
  String get nothingPickedYetFineTooHeart;

  /// No description provided for @nothingPickedYetFineTooCan.
  ///
  /// In en, this message translates to:
  /// **'nothing picked yet is fine too — you can decide later'**
  String get nothingPickedYetFineTooCan;

  /// No description provided for @nothingPlannedRightNow.
  ///
  /// In en, this message translates to:
  /// **'nothing planned right now'**
  String get nothingPlannedRightNow;

  /// No description provided for @nothingSuggestedYetLlShowUp.
  ///
  /// In en, this message translates to:
  /// **'nothing suggested yet — it\'ll show up here'**
  String get nothingSuggestedYetLlShowUp;

  /// No description provided for @nothingTurnedUpTryAnotherTitle.
  ///
  /// In en, this message translates to:
  /// **'nothing turned up for that — try another title'**
  String get nothingTurnedUpTryAnotherTitle;

  /// No description provided for @nothingSLoggedYet.
  ///
  /// In en, this message translates to:
  /// **'nothing\'s logged yet.'**
  String get nothingSLoggedYet;

  /// No description provided for @offByDefaultTitleSSynopsis.
  ///
  /// In en, this message translates to:
  /// **'off by default — a title\'s synopsis is usually written not to '**
  String get offByDefaultTitleSSynopsis;

  /// No description provided for @offlineShowingShorterLocalList.
  ///
  /// In en, this message translates to:
  /// **'offline — showing a shorter local list'**
  String get offlineShowingShorterLocalList;

  /// No description provided for @okayThereLlNewPickTomorrow.
  ///
  /// In en, this message translates to:
  /// **'okay — there\'ll be a new pick tomorrow'**
  String get okayThereLlNewPickTomorrow;

  /// No description provided for @onByDefaultOtherPeopleS.
  ///
  /// In en, this message translates to:
  /// **'on by default — other people\'s reviews say what they want, so '**
  String get onByDefaultOtherPeopleS;

  /// No description provided for @onTanSince.
  ///
  /// In en, this message translates to:
  /// **'on tanè since '**
  String get onTanSince;

  /// No description provided for @onDay.
  ///
  /// In en, this message translates to:
  /// **'on this day'**
  String get onDay;

  /// No description provided for @onceLinkedEveningsPlanTogetherShow.
  ///
  /// In en, this message translates to:
  /// **'once linked, evenings you plan together show up on both '**
  String get onceLinkedEveningsPlanTogetherShow;

  /// No description provided for @oneEveningWeekAlreadyEnough.
  ///
  /// In en, this message translates to:
  /// **'one evening a week is already enough'**
  String get oneEveningWeekAlreadyEnough;

  /// No description provided for @oneMoreLookBeforeSOfficial.
  ///
  /// In en, this message translates to:
  /// **'one more look before it\'s official'**
  String get oneMoreLookBeforeSOfficial;

  /// No description provided for @openCoViewing.
  ///
  /// In en, this message translates to:
  /// **'open co-viewing'**
  String get openCoViewing;

  /// No description provided for @openItsPopupPasteBothValues.
  ///
  /// In en, this message translates to:
  /// **'open its popup and paste both values below'**
  String get openItsPopupPasteBothValues;

  /// No description provided for @openItsSettingsPasteBothValues.
  ///
  /// In en, this message translates to:
  /// **'open its settings and paste both values below'**
  String get openItsSettingsPasteBothValues;

  /// No description provided for @orJustType.
  ///
  /// In en, this message translates to:
  /// **'or just type it in'**
  String get orJustType;

  /// No description provided for @orPickReadyMadeAvatar.
  ///
  /// In en, this message translates to:
  /// **'or pick a ready-made avatar'**
  String get orPickReadyMadeAvatar;

  /// No description provided for @orReadThemCode.
  ///
  /// In en, this message translates to:
  /// **'or read them the code'**
  String get orReadThemCode;

  /// No description provided for @orTryOneThese.
  ///
  /// In en, this message translates to:
  /// **'or try one of these'**
  String get orTryOneThese;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'password'**
  String get password;

  /// No description provided for @pastePublicYoutubeTwitchLinkSingle.
  ///
  /// In en, this message translates to:
  /// **'paste a public YouTube or Twitch link — a single video, a whole '**
  String get pastePublicYoutubeTwitchLinkSingle;

  /// No description provided for @pasteUrlBelow.
  ///
  /// In en, this message translates to:
  /// **'paste the URL below'**
  String get pasteUrlBelow;

  /// No description provided for @peopleMayKnow.
  ///
  /// In en, this message translates to:
  /// **'people you may know'**
  String get peopleMayKnow;

  /// No description provided for @pickPassword.
  ///
  /// In en, this message translates to:
  /// **'pick a password'**
  String get pickPassword;

  /// No description provided for @pickSeat.
  ///
  /// In en, this message translates to:
  /// **'pick a seat'**
  String get pickSeat;

  /// No description provided for @pickTitlePickDateGetTicket.
  ///
  /// In en, this message translates to:
  /// **'pick a title, pick a date, get a ticket'**
  String get pickTitlePickDateGetTicket;

  /// No description provided for @pickBackUpStartFresh.
  ///
  /// In en, this message translates to:
  /// **'pick it back up, or start a fresh'**
  String get pickBackUpStartFresh;

  /// No description provided for @pickUpSame.
  ///
  /// In en, this message translates to:
  /// **'pick up the same'**
  String get pickUpSame;

  /// No description provided for @pickUsername.
  ///
  /// In en, this message translates to:
  /// **'pick a username'**
  String get pickUsername;

  /// No description provided for @pickUs.
  ///
  /// In en, this message translates to:
  /// **'pick for us'**
  String get pickUs;

  /// No description provided for @pickWhatSStillLightsCome.
  ///
  /// In en, this message translates to:
  /// **'pick what\'s still with you as the lights come up'**
  String get pickWhatSStillLightsCome;

  /// No description provided for @pickedFromWhatVeLovedSo.
  ///
  /// In en, this message translates to:
  /// **'picked from what you\'ve loved so far — tap one to watch its trailer'**
  String get pickedFromWhatVeLovedSo;

  /// No description provided for @planEvening.
  ///
  /// In en, this message translates to:
  /// **'plan an evening'**
  String get planEvening;

  /// No description provided for @plannedTogetherWatchWheneverReBoth.
  ///
  /// In en, this message translates to:
  /// **'planned together — watch it whenever you\'re both ready'**
  String get plannedTogetherWatchWheneverReBoth;

  /// No description provided for @pointTheirCode.
  ///
  /// In en, this message translates to:
  /// **'point it at their code'**
  String get pointTheirCode;

  /// No description provided for @premiumFreeDemo.
  ///
  /// In en, this message translates to:
  /// **'premium · free in demo'**
  String get premiumFreeDemo;

  /// No description provided for @pressDownJustTap.
  ///
  /// In en, this message translates to:
  /// **'press it down — or just tap'**
  String get pressDownJustTap;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'privacy'**
  String get privacy;

  /// No description provided for @sincerityPoints.
  ///
  /// In en, this message translates to:
  /// **'sincerity points'**
  String get sincerityPoints;

  /// No description provided for @privateByDefaultChooseWhetherFriends.
  ///
  /// In en, this message translates to:
  /// **'private by default — choose whether friends see this number'**
  String get privateByDefaultChooseWhetherFriends;

  /// No description provided for @private.
  ///
  /// In en, this message translates to:
  /// **'private'**
  String get private;

  /// No description provided for @privateListsLikeYoutubeSWatch.
  ///
  /// In en, this message translates to:
  /// **'private lists like YouTube\'s Watch Later or Liked videos can\'t be '**
  String get privateListsLikeYoutubeSWatch;

  /// No description provided for @propose.
  ///
  /// In en, this message translates to:
  /// **'propose'**
  String get propose;

  /// No description provided for @pullDownTapHereTryAgain.
  ///
  /// In en, this message translates to:
  /// **'pull down, or tap here, to try again'**
  String get pullDownTapHereTryAgain;

  /// No description provided for @pullDownTapRefreshIconAbove.
  ///
  /// In en, this message translates to:
  /// **'pull down, or tap the refresh icon above, to check again'**
  String get pullDownTapRefreshIconAbove;

  /// No description provided for @pullDownTapRefreshIconAbove2.
  ///
  /// In en, this message translates to:
  /// **'pull down, or tap the refresh icon above, to try again'**
  String get pullDownTapRefreshIconAbove2;

  /// No description provided for @putSharedListTonight.
  ///
  /// In en, this message translates to:
  /// **'put on the shared list for tonight.'**
  String get putSharedListTonight;

  /// No description provided for @raiseJustTap.
  ///
  /// In en, this message translates to:
  /// **'raise it — or just tap'**
  String get raiseJustTap;

  /// No description provided for @raisedTonight.
  ///
  /// In en, this message translates to:
  /// **'raised for tonight'**
  String get raisedTonight;

  /// No description provided for @random.
  ///
  /// In en, this message translates to:
  /// **'random'**
  String get random;

  /// No description provided for @randomPick.
  ///
  /// In en, this message translates to:
  /// **'random pick'**
  String get randomPick;

  /// No description provided for @rating.
  ///
  /// In en, this message translates to:
  /// **'rating'**
  String get rating;

  /// No description provided for @route.
  ///
  /// In en, this message translates to:
  /// **'route'**
  String get route;

  /// No description provided for @rolling.
  ///
  /// In en, this message translates to:
  /// **'rolling…'**
  String get rolling;

  /// No description provided for @rutubeMostReliableTheseRestRead.
  ///
  /// In en, this message translates to:
  /// **'Rutube is the most reliable of these; the rest read the page\'s own structured data and may need a quick fix if a service changes its layout (see integrations/browser-extension/README.md for the exact steps)'**
  String get rutubeMostReliableTheseRestRead;

  /// No description provided for @readEntirelyDeviceNothingUploaded.
  ///
  /// In en, this message translates to:
  /// **'read entirely on your device — nothing is uploaded'**
  String get readEntirelyDeviceNothingUploaded;

  /// No description provided for @readFullReview.
  ///
  /// In en, this message translates to:
  /// **'read the full review →'**
  String get readFullReview;

  /// No description provided for @readyShow.
  ///
  /// In en, this message translates to:
  /// **'ready for the show?'**
  String get readyShow;

  /// No description provided for @readyBoard.
  ///
  /// In en, this message translates to:
  /// **'ready to board?'**
  String get readyBoard;

  /// No description provided for @readyPlant.
  ///
  /// In en, this message translates to:
  /// **'ready to plant it?'**
  String get readyPlant;

  /// No description provided for @recentActivity.
  ///
  /// In en, this message translates to:
  /// **'recent activity'**
  String get recentActivity;

  /// No description provided for @recentlyLogged.
  ///
  /// In en, this message translates to:
  /// **'recently logged'**
  String get recentlyLogged;

  /// No description provided for @region.
  ///
  /// In en, this message translates to:
  /// **'region'**
  String get region;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'remove'**
  String get remove;

  /// No description provided for @requested.
  ///
  /// In en, this message translates to:
  /// **'requested'**
  String get requested;

  /// No description provided for @requests.
  ///
  /// In en, this message translates to:
  /// **'requests'**
  String get requests;

  /// No description provided for @respondAbove.
  ///
  /// In en, this message translates to:
  /// **'respond above'**
  String get respondAbove;

  /// No description provided for @retakePhoto.
  ///
  /// In en, this message translates to:
  /// **'retake photo'**
  String get retakePhoto;

  /// No description provided for @review.
  ///
  /// In en, this message translates to:
  /// **'review'**
  String get review;

  /// No description provided for @reviews.
  ///
  /// In en, this message translates to:
  /// **'reviews'**
  String get reviews;

  /// No description provided for @rewatch.
  ///
  /// In en, this message translates to:
  /// **'rewatch'**
  String get rewatch;

  /// No description provided for @riffledOpen.
  ///
  /// In en, this message translates to:
  /// **'riffled open'**
  String get riffledOpen;

  /// No description provided for @rotate.
  ///
  /// In en, this message translates to:
  /// **'rotate'**
  String get rotate;

  /// No description provided for @rotateToken.
  ///
  /// In en, this message translates to:
  /// **'rotate token'**
  String get rotateToken;

  /// No description provided for @rotateToken2.
  ///
  /// In en, this message translates to:
  /// **'rotate your token?'**
  String get rotateToken2;

  /// No description provided for @sameBrowserExtensionAboveOneInstall.
  ///
  /// In en, this message translates to:
  /// **'same browser extension as above — one install, one server/token pair covers every site it knows how to read'**
  String get sameBrowserExtensionAboveOneInstall;

  /// No description provided for @sameChoiceLayersButtonRouteMap.
  ///
  /// In en, this message translates to:
  /// **'same choice as the layers button on the route map itself'**
  String get sameChoiceLayersButtonRouteMap;

  /// No description provided for @sameDiaryEitherWayJustDifferent.
  ///
  /// In en, this message translates to:
  /// **'same diary either way — just a different little ritual'**
  String get sameDiaryEitherWayJustDifferent;

  /// No description provided for @sameDiaryEitherWayJustDifferent2.
  ///
  /// In en, this message translates to:
  /// **'same diary either way — just a different little ritual for closing out an evening'**
  String get sameDiaryEitherWayJustDifferent2;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'save'**
  String get save;

  /// No description provided for @saveCard.
  ///
  /// In en, this message translates to:
  /// **'save this as a card'**
  String get saveCard;

  /// No description provided for @scanTicket.
  ///
  /// In en, this message translates to:
  /// **'scan a ticket'**
  String get scanTicket;

  /// No description provided for @scanTheirCodeInstead.
  ///
  /// In en, this message translates to:
  /// **'scan their code instead'**
  String get scanTheirCodeInstead;

  /// No description provided for @sealedTonight.
  ///
  /// In en, this message translates to:
  /// **'sealed for tonight'**
  String get sealedTonight;

  /// No description provided for @searchFilmShowGame.
  ///
  /// In en, this message translates to:
  /// **'search a film, show, or game'**
  String get searchFilmShowGame;

  /// No description provided for @searchUsernameAboveInviteSomeoneWho.
  ///
  /// In en, this message translates to:
  /// **'search a username above, or invite someone who isn\'t on tanè yet'**
  String get searchUsernameAboveInviteSomeoneWho;

  /// No description provided for @searchFilmDRewatchTonight.
  ///
  /// In en, this message translates to:
  /// **'search for a film you\'d rewatch tonight'**
  String get searchFilmDRewatchTonight;

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'search for a title…'**
  String get searchTitle;

  /// No description provided for @searchMovies.
  ///
  /// In en, this message translates to:
  /// **'search movies…'**
  String get searchMovies;

  /// No description provided for @seasons.
  ///
  /// In en, this message translates to:
  /// **'seasons'**
  String get seasons;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'see all'**
  String get seeAll;

  /// No description provided for @seeAll2.
  ///
  /// In en, this message translates to:
  /// **'see all ›'**
  String get seeAll2;

  /// No description provided for @sendThemCode.
  ///
  /// In en, this message translates to:
  /// **'send them this code'**
  String get sendThemCode;

  /// No description provided for @sendPartnerSWaitingThemEnter.
  ///
  /// In en, this message translates to:
  /// **'send this to your partner — it\'s waiting for them to enter it.'**
  String get sendPartnerSWaitingThemEnter;

  /// No description provided for @sent.
  ///
  /// In en, this message translates to:
  /// **'sent'**
  String get sent;

  /// No description provided for @server.
  ///
  /// In en, this message translates to:
  /// **'server'**
  String get server;

  /// No description provided for @setUp.
  ///
  /// In en, this message translates to:
  /// **'set it up →'**
  String get setUp;

  /// No description provided for @soReHereMostly.
  ///
  /// In en, this message translates to:
  /// **'so — you\'re here mostly for'**
  String get soReHereMostly;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'settings'**
  String get settings;

  /// No description provided for @settledTogether.
  ///
  /// In en, this message translates to:
  /// **'settled, together'**
  String get settledTogether;

  /// No description provided for @showAll.
  ///
  /// In en, this message translates to:
  /// **'show all'**
  String get showAll;

  /// No description provided for @showMeEverything.
  ///
  /// In en, this message translates to:
  /// **'show me everything'**
  String get showMeEverything;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'share'**
  String get share;

  /// No description provided for @shareInvite.
  ///
  /// In en, this message translates to:
  /// **'share invite'**
  String get shareInvite;

  /// No description provided for @shareEvening.
  ///
  /// In en, this message translates to:
  /// **'share this evening'**
  String get shareEvening;

  /// No description provided for @shareTitle.
  ///
  /// In en, this message translates to:
  /// **'share this title'**
  String get shareTitle;

  /// No description provided for @russianInterface.
  ///
  /// In en, this message translates to:
  /// **'russian interface'**
  String get russianInterface;

  /// No description provided for @translatesWholeAppTitlesTooWhen.
  ///
  /// In en, this message translates to:
  /// **'translates the whole app — titles too, when TMDB has one, otherwise English'**
  String get translatesWholeAppTitlesTooWhen;

  /// No description provided for @trip.
  ///
  /// In en, this message translates to:
  /// **'trip'**
  String get trip;

  /// No description provided for @showTodaySPickHome.
  ///
  /// In en, this message translates to:
  /// **'show today\'s pick on Home'**
  String get showTodaySPickHome;

  /// No description provided for @showsTheseAlongsideMoviesShowsWatched.
  ///
  /// In en, this message translates to:
  /// **'shows these alongside movies and shows in watched, watching, '**
  String get showsTheseAlongsideMoviesShowsWatched;

  /// No description provided for @showtime.
  ///
  /// In en, this message translates to:
  /// **'showtime'**
  String get showtime;

  /// No description provided for @shuffleAgain.
  ///
  /// In en, this message translates to:
  /// **'shuffle again'**
  String get shuffleAgain;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'skip'**
  String get skip;

  /// No description provided for @skipRitual.
  ///
  /// In en, this message translates to:
  /// **'skip the ritual'**
  String get skipRitual;

  /// No description provided for @skipRitualJustLogNow.
  ///
  /// In en, this message translates to:
  /// **'skip the ritual — just log it now'**
  String get skipRitualJustLogNow;

  /// No description provided for @spinReel.
  ///
  /// In en, this message translates to:
  /// **'spin the reel'**
  String get spinReel;

  /// No description provided for @spin.
  ///
  /// In en, this message translates to:
  /// **'spin'**
  String get spin;

  /// No description provided for @shortIOnlyHaveHour.
  ///
  /// In en, this message translates to:
  /// **'short, I only have an hour'**
  String get shortIOnlyHaveHour;

  /// No description provided for @spinning.
  ///
  /// In en, this message translates to:
  /// **'spinning…'**
  String get spinning;

  /// No description provided for @spoilers.
  ///
  /// In en, this message translates to:
  /// **'spoilers'**
  String get spoilers;

  /// No description provided for @startTypingCityName.
  ///
  /// In en, this message translates to:
  /// **'start typing a city name'**
  String get startTypingCityName;

  /// No description provided for @startNew.
  ///
  /// In en, this message translates to:
  /// **'start new'**
  String get startNew;

  /// No description provided for @startDiary.
  ///
  /// In en, this message translates to:
  /// **'start your diary'**
  String get startDiary;

  /// No description provided for @stay.
  ///
  /// In en, this message translates to:
  /// **'stay'**
  String get stay;

  /// No description provided for @stillRollingThroughDark.
  ///
  /// In en, this message translates to:
  /// **'still rolling through the dark'**
  String get stillRollingThroughDark;

  /// No description provided for @stillUp.
  ///
  /// In en, this message translates to:
  /// **'still up?'**
  String get stillUp;

  /// No description provided for @streamingDataProvidedByJustwatch.
  ///
  /// In en, this message translates to:
  /// **'streaming data provided by JustWatch'**
  String get streamingDataProvidedByJustwatch;

  /// No description provided for @streamingRegion.
  ///
  /// In en, this message translates to:
  /// **'streaming region'**
  String get streamingRegion;

  /// No description provided for @swipeThrough.
  ///
  /// In en, this message translates to:
  /// **'swipe through'**
  String get swipeThrough;

  /// No description provided for @swipeThroughJustContinueLlFind.
  ///
  /// In en, this message translates to:
  /// **'swipe through, or just continue — you\'ll find it all later anyway'**
  String get swipeThroughJustContinueLlFind;

  /// No description provided for @takePhotoWeLlPullTitle.
  ///
  /// In en, this message translates to:
  /// **'take a photo of it and we\'ll pull the title off it, straight into '**
  String get takePhotoWeLlPullTitle;

  /// No description provided for @tapAnyBadgeSeeWhatS.
  ///
  /// In en, this message translates to:
  /// **'tap any badge to see what it\'s for'**
  String get tapAnyBadgeSeeWhatS;

  /// No description provided for @tapProposeAnyThesePutUp.
  ///
  /// In en, this message translates to:
  /// **'tap propose on any of these to put it up for a vote'**
  String get tapProposeAnyThesePutUp;

  /// No description provided for @tapSpinStart.
  ///
  /// In en, this message translates to:
  /// **'tap spin to start'**
  String get tapSpinStart;

  /// No description provided for @tapAddOne.
  ///
  /// In en, this message translates to:
  /// **'tap to add one'**
  String get tapAddOne;

  /// No description provided for @noneYet.
  ///
  /// In en, this message translates to:
  /// **'none yet ›'**
  String get noneYet;

  /// No description provided for @tapAgreeWatchTogether.
  ///
  /// In en, this message translates to:
  /// **'tap to agree — watch it together'**
  String get tapAgreeWatchTogether;

  /// No description provided for @tapReveal.
  ///
  /// In en, this message translates to:
  /// **'tap to reveal'**
  String get tapReveal;

  /// No description provided for @tapSeeEveryone.
  ///
  /// In en, this message translates to:
  /// **'tap to see everyone'**
  String get tapSeeEveryone;

  /// No description provided for @tapTryAgain.
  ///
  /// In en, this message translates to:
  /// **'tap to try again'**
  String get tapTryAgain;

  /// No description provided for @tan.
  ///
  /// In en, this message translates to:
  /// **'tanè'**
  String get tan;

  /// No description provided for @tanPickedThese.
  ///
  /// In en, this message translates to:
  /// **'tanè picked these'**
  String get tanPickedThese;

  /// No description provided for @tanPicks.
  ///
  /// In en, this message translates to:
  /// **'tanè picks'**
  String get tanPicks;

  /// No description provided for @tanV010.
  ///
  /// In en, this message translates to:
  /// **'tanè · v0.1.0'**
  String get tanV010;

  /// No description provided for @teamira2.
  ///
  /// In en, this message translates to:
  /// **'teamira'**
  String get teamira2;

  /// No description provided for @tanSOwnWordsStayEnglish.
  ///
  /// In en, this message translates to:
  /// **'tanè\'s own words stay in English everywhere — this just '**
  String get tanSOwnWordsStayEnglish;

  /// No description provided for @tearContinue.
  ///
  /// In en, this message translates to:
  /// **'tear to continue'**
  String get tearContinue;

  /// No description provided for @thankTonight.
  ///
  /// In en, this message translates to:
  /// **'thank you for tonight'**
  String get thankTonight;

  /// No description provided for @thatDidnTGoThroughTry.
  ///
  /// In en, this message translates to:
  /// **'that didn\'t go through — try again'**
  String get thatDidnTGoThroughTry;

  /// No description provided for @thatDidnTSaveTryAgain.
  ///
  /// In en, this message translates to:
  /// **'that didn\'t save — try again'**
  String get thatDidnTSaveTryAgain;

  /// No description provided for @thatS3TodayMoreTomorrow.
  ///
  /// In en, this message translates to:
  /// **'that\'s 3 for today — more tomorrow'**
  String get thatS3TodayMoreTomorrow;

  /// No description provided for @thatSWholePile.
  ///
  /// In en, this message translates to:
  /// **'that\'s the whole pile'**
  String get thatSWholePile;

  /// No description provided for @theBedSettlesNight.
  ///
  /// In en, this message translates to:
  /// **'the bed settles for the night'**
  String get theBedSettlesNight;

  /// No description provided for @theClassicsComfortRewatchesWhateverComes.
  ///
  /// In en, this message translates to:
  /// **'the classics, the comfort rewatches, whatever comes to mind first'**
  String get theClassicsComfortRewatchesWhateverComes;

  /// No description provided for @theDewHasnTSettledYet.
  ///
  /// In en, this message translates to:
  /// **'the dew hasn\'t settled yet'**
  String get theDewHasnTSettledYet;

  /// No description provided for @theFlameCountsConsecutiveEveningsLeast.
  ///
  /// In en, this message translates to:
  /// **'the flame counts consecutive evenings with at least one '**
  String get theFlameCountsConsecutiveEveningsLeast;

  /// No description provided for @theLightsStillDown.
  ///
  /// In en, this message translates to:
  /// **'the lights are still down'**
  String get theLightsStillDown;

  /// No description provided for @theLog.
  ///
  /// In en, this message translates to:
  /// **'the log'**
  String get theLog;

  /// No description provided for @tapExplore.
  ///
  /// In en, this message translates to:
  /// **'tap to explore'**
  String get tapExplore;

  /// No description provided for @levelUp.
  ///
  /// In en, this message translates to:
  /// **'level up'**
  String get levelUp;

  /// No description provided for @seriesComplete.
  ///
  /// In en, this message translates to:
  /// **'series complete'**
  String get seriesComplete;

  /// No description provided for @seasonComplete.
  ///
  /// In en, this message translates to:
  /// **'season complete'**
  String get seasonComplete;

  /// No description provided for @theProgramme.
  ///
  /// In en, this message translates to:
  /// **'the programme'**
  String get theProgramme;

  /// No description provided for @theRoute.
  ///
  /// In en, this message translates to:
  /// **'the route'**
  String get theRoute;

  /// No description provided for @theScreenComesAlive.
  ///
  /// In en, this message translates to:
  /// **'the screen comes alive'**
  String get theScreenComesAlive;

  /// No description provided for @theTitlesThemselvesStayDiaryOnly.
  ///
  /// In en, this message translates to:
  /// **'the titles themselves stay in your diary — only the list goes away'**
  String get theTitlesThemselvesStayDiaryOnly;

  /// No description provided for @theWindowGarden.
  ///
  /// In en, this message translates to:
  /// **'the window garden'**
  String get theWindowGarden;

  /// No description provided for @these.
  ///
  /// In en, this message translates to:
  /// **'these are'**
  String get these;

  /// No description provided for @theseTitles.
  ///
  /// In en, this message translates to:
  /// **'these titles are'**
  String get theseTitles;

  /// No description provided for @theyLlJoinOnceTheyAccept.
  ///
  /// In en, this message translates to:
  /// **'they\'ll join once they accept — same as any co-viewing invite.'**
  String get theyLlJoinOnceTheyAccept;

  /// No description provided for @thisDiary.
  ///
  /// In en, this message translates to:
  /// **'this diary'**
  String get thisDiary;

  /// No description provided for @thisServerIsnTSetUp.
  ///
  /// In en, this message translates to:
  /// **'this server isn\'t set up for that platform yet'**
  String get thisServerIsnTSetUp;

  /// No description provided for @thisClosesCoViewingBetweenTwo.
  ///
  /// In en, this message translates to:
  /// **'this closes co-viewing between you two — what\'s already in each of your diaries stays put.'**
  String get thisClosesCoViewingBetweenTwo;

  /// No description provided for @thisSharedListSeparateFromOwn.
  ///
  /// In en, this message translates to:
  /// **'this shared list is separate from your own \"plan to watch\" '**
  String get thisSharedListSeparateFromOwn;

  /// No description provided for @titleLanguage.
  ///
  /// In en, this message translates to:
  /// **'title language'**
  String get titleLanguage;

  /// No description provided for @toPlanWatch.
  ///
  /// In en, this message translates to:
  /// **'to plan to watch'**
  String get toPlanWatch;

  /// No description provided for @todaySPick.
  ///
  /// In en, this message translates to:
  /// **'today\'s pick'**
  String get todaySPick;

  /// No description provided for @together.
  ///
  /// In en, this message translates to:
  /// **'together'**
  String get together;

  /// No description provided for @token.
  ///
  /// In en, this message translates to:
  /// **'token'**
  String get token;

  /// No description provided for @tonightSafelyLogged.
  ///
  /// In en, this message translates to:
  /// **'tonight, safely logged'**
  String get tonightSafelyLogged;

  /// No description provided for @tonightSScreen.
  ///
  /// In en, this message translates to:
  /// **'tonight\'s screen'**
  String get tonightSScreen;

  /// No description provided for @touchWhatFeelsLike.
  ///
  /// In en, this message translates to:
  /// **'touch what feels like you'**
  String get touchWhatFeelsLike;

  /// No description provided for @trailers.
  ///
  /// In en, this message translates to:
  /// **'trailers'**
  String get trailers;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'try again'**
  String get tryAgain;

  /// No description provided for @tryTan.
  ///
  /// In en, this message translates to:
  /// **'try tanè'**
  String get tryTan;

  /// No description provided for @tuckedAwayTonight.
  ///
  /// In en, this message translates to:
  /// **'tucked away for tonight'**
  String get tuckedAwayTonight;

  /// No description provided for @tucked.
  ///
  /// In en, this message translates to:
  /// **'tucked in'**
  String get tucked;

  /// No description provided for @tuckedIntoPlanWatch.
  ///
  /// In en, this message translates to:
  /// **'tucked into plan to watch'**
  String get tuckedIntoPlanWatch;

  /// No description provided for @tugApartJustTap.
  ///
  /// In en, this message translates to:
  /// **'tug it apart — or just tap'**
  String get tugApartJustTap;

  /// No description provided for @type6CharacterCodeOtherPerson.
  ///
  /// In en, this message translates to:
  /// **'type in the 6-character code the other person sent you.'**
  String get type6CharacterCodeOtherPerson;

  /// No description provided for @typePasteAnyMixThemBelow.
  ///
  /// In en, this message translates to:
  /// **'type or paste any mix of them below, one per line — tanè '**
  String get typePasteAnyMixThemBelow;

  /// No description provided for @updatedComeBackMenuAnytimeBring.
  ///
  /// In en, this message translates to:
  /// **'updated — come back to this menu anytime to bring a tab back'**
  String get updatedComeBackMenuAnytimeBring;

  /// No description provided for @unlinkFrom.
  ///
  /// In en, this message translates to:
  /// **'unlink from'**
  String get unlinkFrom;

  /// No description provided for @uploadOwnPhoto.
  ///
  /// In en, this message translates to:
  /// **'upload your own photo'**
  String get uploadOwnPhoto;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'username'**
  String get username;

  /// No description provided for @voteOut.
  ///
  /// In en, this message translates to:
  /// **'vote it out'**
  String get voteOut;

  /// No description provided for @voteSomethingElse.
  ///
  /// In en, this message translates to:
  /// **'vote on something else'**
  String get voteSomethingElse;

  /// No description provided for @voteTogether.
  ///
  /// In en, this message translates to:
  /// **'vote together'**
  String get voteTogether;

  /// No description provided for @votingUntil.
  ///
  /// In en, this message translates to:
  /// **'voting until'**
  String get votingUntil;

  /// No description provided for @waitingThemJoin.
  ///
  /// In en, this message translates to:
  /// **'waiting for them to join…'**
  String get waitingThemJoin;

  /// No description provided for @walk.
  ///
  /// In en, this message translates to:
  /// **'walk'**
  String get walk;

  /// No description provided for @weirdMindBending.
  ///
  /// In en, this message translates to:
  /// **'weird and mind-bending'**
  String get weirdMindBending;

  /// No description provided for @wrappingUp.
  ///
  /// In en, this message translates to:
  /// **'wrapping up…'**
  String get wrappingUp;

  /// No description provided for @watchNextEpisode.
  ///
  /// In en, this message translates to:
  /// **'watch the next episode?'**
  String get watchNextEpisode;

  /// No description provided for @watchTogether.
  ///
  /// In en, this message translates to:
  /// **'watch together'**
  String get watchTogether;

  /// No description provided for @watchTrailer.
  ///
  /// In en, this message translates to:
  /// **'watch trailer'**
  String get watchTrailer;

  /// No description provided for @watched.
  ///
  /// In en, this message translates to:
  /// **'watched'**
  String get watched;

  /// No description provided for @planned.
  ///
  /// In en, this message translates to:
  /// **'planned'**
  String get planned;

  /// No description provided for @suggested.
  ///
  /// In en, this message translates to:
  /// **'suggested'**
  String get suggested;

  /// No description provided for @watchedAgain.
  ///
  /// In en, this message translates to:
  /// **'watched again'**
  String get watchedAgain;

  /// No description provided for @watchedFeltLike.
  ///
  /// In en, this message translates to:
  /// **'watched it with... felt like...'**
  String get watchedFeltLike;

  /// No description provided for @whateverEndUpWatching.
  ///
  /// In en, this message translates to:
  /// **'whatever you end up watching'**
  String get whateverEndUpWatching;

  /// No description provided for @watchingSeries.
  ///
  /// In en, this message translates to:
  /// **'watching · series'**
  String get watchingSeries;

  /// No description provided for @weLlBringBackAroundMonth.
  ///
  /// In en, this message translates to:
  /// **'we\'ll bring it back around — a month from now, and again next year'**
  String get weLlBringBackAroundMonth;

  /// No description provided for @welcomeBackEveningDiary.
  ///
  /// In en, this message translates to:
  /// **'welcome back to your evening diary'**
  String get welcomeBackEveningDiary;

  /// No description provided for @whatWeMood.
  ///
  /// In en, this message translates to:
  /// **'what are we in the mood for?'**
  String get whatWeMood;

  /// No description provided for @whatDidThink.
  ///
  /// In en, this message translates to:
  /// **'what did you think?'**
  String get whatDidThink;

  /// No description provided for @whatShallWeWatch.
  ///
  /// In en, this message translates to:
  /// **'what shall we watch?'**
  String get whatShallWeWatch;

  /// No description provided for @whatShouldComeFrom.
  ///
  /// In en, this message translates to:
  /// **'what should it come from?'**
  String get whatShouldComeFrom;

  /// No description provided for @whatShouldDeckComeFrom.
  ///
  /// In en, this message translates to:
  /// **'what should the deck come from?'**
  String get whatShouldDeckComeFrom;

  /// No description provided for @whatShouldShortlistComeFrom.
  ///
  /// In en, this message translates to:
  /// **'what should the shortlist come from?'**
  String get whatShouldShortlistComeFrom;

  /// No description provided for @whatStayed.
  ///
  /// In en, this message translates to:
  /// **'what stayed with you?'**
  String get whatStayed;

  /// No description provided for @whatTime.
  ///
  /// In en, this message translates to:
  /// **'what time?'**
  String get whatTime;

  /// No description provided for @whateverLandEveryoneVotesYesFirst.
  ///
  /// In en, this message translates to:
  /// **'whatever you land on, everyone votes yes first'**
  String get whateverLandEveryoneVotesYesFirst;

  /// No description provided for @when.
  ///
  /// In en, this message translates to:
  /// **'when'**
  String get when;

  /// No description provided for @whenTmdbHasTranslationOtherwiseEnglish.
  ///
  /// In en, this message translates to:
  /// **'when TMDB has a translation for it — otherwise English'**
  String get whenTmdbHasTranslationOtherwiseEnglish;

  /// No description provided for @whenWatchTogetherMatchHappensOne.
  ///
  /// In en, this message translates to:
  /// **'when a Watch Together match happens — one phone or over the '**
  String get whenWatchTogetherMatchHappensOne;

  /// No description provided for @whereWatch.
  ///
  /// In en, this message translates to:
  /// **'where to watch'**
  String get whereWatch;

  /// No description provided for @whereXpComesFrom.
  ///
  /// In en, this message translates to:
  /// **'where your xp comes from'**
  String get whereXpComesFrom;

  /// No description provided for @whichCountrySStreamingInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'which country\'s streaming info a title shows — change this '**
  String get whichCountrySStreamingInfoTitle;

  /// No description provided for @whichCountrySServicesShowUnder.
  ///
  /// In en, this message translates to:
  /// **'which country\'s services show under \"where to watch\" '**
  String get whichCountrySServicesShowUnder;

  /// No description provided for @whichOneMine.
  ///
  /// In en, this message translates to:
  /// **'which one is mine?'**
  String get whichOneMine;

  /// No description provided for @whoCanSeeWhatVeWatched.
  ///
  /// In en, this message translates to:
  /// **'who can see what you\'ve watched, are watching now, plan to watch, or have marked as a favorite'**
  String get whoCanSeeWhatVeWatched;

  /// No description provided for @whoStoleShow.
  ///
  /// In en, this message translates to:
  /// **'who stole the show?'**
  String get whoStoleShow;

  /// No description provided for @whoStoodOutTonight.
  ///
  /// In en, this message translates to:
  /// **'who stood out tonight?'**
  String get whoStoodOutTonight;

  /// No description provided for @wonTAskAgainTurnSkip.
  ///
  /// In en, this message translates to:
  /// **'won\'t ask again — turn on \"skip the ritual\" in settings any time'**
  String get wonTAskAgainTurnSkip;

  /// No description provided for @writeMoreFullPage.
  ///
  /// In en, this message translates to:
  /// **'write more, full page'**
  String get writeMoreFullPage;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'yes'**
  String get yes;

  /// No description provided for @yesContinue.
  ///
  /// In en, this message translates to:
  /// **'yes, continue'**
  String get yesContinue;

  /// No description provided for @youHavenTAddedAnyFriends.
  ///
  /// In en, this message translates to:
  /// **'you haven\'t added any friends yet — search a username or invite someone'**
  String get youHavenTAddedAnyFriends;

  /// No description provided for @youLlNeedNewRequestFriends.
  ///
  /// In en, this message translates to:
  /// **'you\'ll need a new request to be friends again.'**
  String get youLlNeedNewRequestFriends;

  /// No description provided for @youLlLeaveCircleEveryoneElse.
  ///
  /// In en, this message translates to:
  /// **'you\'ll leave the circle — everyone else keeps it going, and what\'s already in your own diary stays put.'**
  String get youLlLeaveCircleEveryoneElse;

  /// No description provided for @youLlStopSeeingEachOther.
  ///
  /// In en, this message translates to:
  /// **'you\'ll stop seeing each other\'s activity — either of you can send a new request later.'**
  String get youLlStopSeeingEachOther;

  /// No description provided for @youReStill.
  ///
  /// In en, this message translates to:
  /// **'you\'re still on'**
  String get youReStill;

  /// No description provided for @youReThroughDeck.
  ///
  /// In en, this message translates to:
  /// **'you\'re through the deck'**
  String get youReThroughDeck;

  /// No description provided for @yourYoutubeTwitchSourcesWillShow.
  ///
  /// In en, this message translates to:
  /// **'your YouTube and Twitch sources will show up alongside movies and '**
  String get yourYoutubeTwitchSourcesWillShow;

  /// No description provided for @yourBunnies.
  ///
  /// In en, this message translates to:
  /// **'your bunnies'**
  String get yourBunnies;

  /// No description provided for @yourEveningsTitle.
  ///
  /// In en, this message translates to:
  /// **'your evenings with this title'**
  String get yourEveningsTitle;

  /// No description provided for @yourLevelHereComesFromReal.
  ///
  /// In en, this message translates to:
  /// **'your level here comes from real evenings — what you log, the notes you write, '**
  String get yourLevelHereComesFromReal;

  /// No description provided for @yourLists.
  ///
  /// In en, this message translates to:
  /// **'your lists'**
  String get yourLists;

  /// No description provided for @yourMarathon.
  ///
  /// In en, this message translates to:
  /// **'your marathon'**
  String get yourMarathon;

  /// No description provided for @yourOwnStatus.
  ///
  /// In en, this message translates to:
  /// **'your own status'**
  String get yourOwnStatus;

  /// No description provided for @yourOwnTag.
  ///
  /// In en, this message translates to:
  /// **'your own tag...'**
  String get yourOwnTag;

  /// No description provided for @yourPlannedEvenings.
  ///
  /// In en, this message translates to:
  /// **'your planned evenings'**
  String get yourPlannedEvenings;

  /// No description provided for @yourProfile.
  ///
  /// In en, this message translates to:
  /// **'your profile'**
  String get yourProfile;

  /// No description provided for @yourRegion.
  ///
  /// In en, this message translates to:
  /// **'your region'**
  String get yourRegion;

  /// No description provided for @yourReview.
  ///
  /// In en, this message translates to:
  /// **'your review'**
  String get yourReview;

  /// No description provided for @yourSources.
  ///
  /// In en, this message translates to:
  /// **'your sources'**
  String get yourSources;

  /// No description provided for @yourStreet.
  ///
  /// In en, this message translates to:
  /// **'your street'**
  String get yourStreet;

  /// No description provided for @yourWrapped.
  ///
  /// In en, this message translates to:
  /// **'your wrapped'**
  String get yourWrapped;

  /// No description provided for @yourYearGlance.
  ///
  /// In en, this message translates to:
  /// **'your year, at a glance'**
  String get yourYearGlance;

  /// No description provided for @premium.
  ///
  /// In en, this message translates to:
  /// **'premium'**
  String get premium;

  /// No description provided for @goPremium.
  ///
  /// In en, this message translates to:
  /// **'go premium'**
  String get goPremium;

  /// No description provided for @unlimitedAiAsksFavoritesShuttleTheme.
  ///
  /// In en, this message translates to:
  /// **'unlimited ai asks, favorites, and the shuttle theme'**
  String get unlimitedAiAsksFavoritesShuttleTheme;

  /// No description provided for @premium2.
  ///
  /// In en, this message translates to:
  /// **'premium is on'**
  String get premium2;

  /// No description provided for @giftSubscription.
  ///
  /// In en, this message translates to:
  /// **'gift a subscription'**
  String get giftSubscription;

  /// No description provided for @aLittleCheaperThanRegularPrice.
  ///
  /// In en, this message translates to:
  /// **'a little cheaper than the regular price'**
  String get aLittleCheaperThanRegularPrice;

  /// No description provided for @text2.
  ///
  /// In en, this message translates to:
  /// **'·'**
  String get text2;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'today'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get yesterday;

  /// No description provided for @tonight.
  ///
  /// In en, this message translates to:
  /// **'tonight'**
  String get tonight;

  /// No description provided for @tomorrow.
  ///
  /// In en, this message translates to:
  /// **'tomorrow'**
  String get tomorrow;

  /// No description provided for @wasEvening.
  ///
  /// In en, this message translates to:
  /// **'was this evening'**
  String get wasEvening;

  /// No description provided for @wasEveningDidWatch.
  ///
  /// In en, this message translates to:
  /// **'was this evening — did you watch it?'**
  String get wasEveningDidWatch;

  /// No description provided for @tonightSNight.
  ///
  /// In en, this message translates to:
  /// **'tonight\'s the night'**
  String get tonightSNight;

  /// No description provided for @jan.
  ///
  /// In en, this message translates to:
  /// **'jan'**
  String get jan;

  /// No description provided for @feb.
  ///
  /// In en, this message translates to:
  /// **'feb'**
  String get feb;

  /// No description provided for @mar.
  ///
  /// In en, this message translates to:
  /// **'mar'**
  String get mar;

  /// No description provided for @apr.
  ///
  /// In en, this message translates to:
  /// **'apr'**
  String get apr;

  /// No description provided for @may.
  ///
  /// In en, this message translates to:
  /// **'may'**
  String get may;

  /// No description provided for @jun.
  ///
  /// In en, this message translates to:
  /// **'jun'**
  String get jun;

  /// No description provided for @jul.
  ///
  /// In en, this message translates to:
  /// **'jul'**
  String get jul;

  /// No description provided for @aug.
  ///
  /// In en, this message translates to:
  /// **'aug'**
  String get aug;

  /// No description provided for @sep.
  ///
  /// In en, this message translates to:
  /// **'sep'**
  String get sep;

  /// No description provided for @oct.
  ///
  /// In en, this message translates to:
  /// **'oct'**
  String get oct;

  /// No description provided for @nov.
  ///
  /// In en, this message translates to:
  /// **'nov'**
  String get nov;

  /// No description provided for @dec.
  ///
  /// In en, this message translates to:
  /// **'dec'**
  String get dec;

  /// No description provided for @closestMatchRecommended.
  ///
  /// In en, this message translates to:
  /// **'closest match · recommended'**
  String get closestMatchRecommended;

  /// No description provided for @closestMatchesTonight.
  ///
  /// In en, this message translates to:
  /// **'closest matches to tonight'**
  String get closestMatchesTonight;

  /// No description provided for @coViewing.
  ///
  /// In en, this message translates to:
  /// **'co-viewing'**
  String get coViewing;

  /// No description provided for @coViewingSettings.
  ///
  /// In en, this message translates to:
  /// **'co-viewing settings'**
  String get coViewingSettings;

  /// No description provided for @coaxPetalsApartJustTap.
  ///
  /// In en, this message translates to:
  /// **'coax the petals apart — or just tap'**
  String get coaxPetalsApartJustTap;

  /// No description provided for @aCoViewingEvening.
  ///
  /// In en, this message translates to:
  /// **'a co-viewing evening'**
  String get aCoViewingEvening;

  /// No description provided for @aCozyEveningDiaryWhatWatch2.
  ///
  /// In en, this message translates to:
  /// **'a cozy evening diary for what you watch — not a tracker dashboard, not a leaderboard. just a quiet place to remember the evenings.'**
  String get aCozyEveningDiaryWhatWatch2;

  /// No description provided for @aFranchiseMarathonPickedFreshMost2.
  ///
  /// In en, this message translates to:
  /// **'a franchise to marathon, picked fresh most days, with a little progress bar for however much of it you\'ve already seen — there\'s a shuffle button on the card itself if it\'s not your thing that day. turn this off if you\'d rather Home stayed without it.'**
  String get aFranchiseMarathonPickedFreshMost2;

  /// No description provided for @aShortlistCountdownWhoeverSGot2.
  ///
  /// In en, this message translates to:
  /// **'a shortlist, a countdown, whoever\'s got the most votes when time\'s up — a tie just runs another round between whoever\'s left.'**
  String get aShortlistCountdownWhoeverSGot2;

  /// No description provided for @alreadyKeepingTrackSomewhereElseBring2.
  ///
  /// In en, this message translates to:
  /// **'already keeping track somewhere else? bring it over — paste a plain list of titles, or an export from any of the services below, and tanè will match each one against the right shelf on its own.'**
  String get alreadyKeepingTrackSomewhereElseBring2;

  /// No description provided for @autoTrackingPicksUpFromPlex2.
  ///
  /// In en, this message translates to:
  /// **'auto-tracking picks it up from Plex, Jellyfin, Kodi or your browser and logs it here on its own — set it up once'**
  String get autoTrackingPicksUpFromPlex2;

  /// No description provided for @everyUrlVeAlreadyPastedInto2.
  ///
  /// In en, this message translates to:
  /// **'every URL you\'ve already pasted into Plex, Jellyfin, Kodi, or the browser extension stops working — you\'ll need to paste the new one into each of them again.'**
  String get everyUrlVeAlreadyPastedInto2;

  /// No description provided for @everyoneReFriendsAlreadyHereAdd2.
  ///
  /// In en, this message translates to:
  /// **'everyone you\'re friends with is already here — add more friends first, then invite them from here.'**
  String get everyoneReFriendsAlreadyHereAdd2;

  /// No description provided for @justHandfulNotEverythingVeEver2.
  ///
  /// In en, this message translates to:
  /// **'just a handful — not everything you\'ve ever watched, that part comes next when you import your history. Pick a few favorites here and \"for you\" on your home screen starts leaning toward them right away.'**
  String get justHandfulNotEverythingVeEver2;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get justNow;

  /// No description provided for @leaveAloneAnythingPickFewNarrow2.
  ///
  /// In en, this message translates to:
  /// **'leave this alone for anything — pick a few to narrow the deck down to just those'**
  String get leaveAloneAnythingPickFewNarrow2;

  /// No description provided for @markWatchedLetPlanGo.
  ///
  /// In en, this message translates to:
  /// **'mark it watched, or let this plan go'**
  String get markWatchedLetPlanGo;

  /// No description provided for @noAccountMatchNoProblemBox2.
  ///
  /// In en, this message translates to:
  /// **'no account to match? no problem — the box below is exactly what \"or just type it in\" above is talking about.'**
  String get noAccountMatchNoProblemBox2;

  /// No description provided for @noStreaksKeepNothingFallBehind2.
  ///
  /// In en, this message translates to:
  /// **'no streaks to keep and nothing to fall behind on — log an evening whenever you actually have one, and tanè quietly fills in around it.'**
  String get noStreaksKeepNothingFallBehind2;

  /// No description provided for @normallyLogSomethingByOpeningApp2.
  ///
  /// In en, this message translates to:
  /// **'normally you log something by opening the app yourself. auto-tracking flips that around: you connect one thing below, one time, and after that, finishing an episode or a movie somewhere else logs it here on its own — no app, no remembering.'**
  String get normallyLogSomethingByOpeningApp2;

  /// No description provided for @nothingHereYetPasteYoutubeTwitch2.
  ///
  /// In en, this message translates to:
  /// **'nothing here yet — paste a YouTube or Twitch link to bring something over'**
  String get nothingHereYetPasteYoutubeTwitch2;

  /// No description provided for @nothingPlanWatchShelfYetSearch2.
  ///
  /// In en, this message translates to:
  /// **'nothing on your plan-to-watch shelf yet — search for a title above, or add a few to that shelf first.'**
  String get nothingPlanWatchShelfYetSearch2;

  /// No description provided for @offByDefaultTitleSSynopsis2.
  ///
  /// In en, this message translates to:
  /// **'off by default — a title\'s synopsis is usually written not to give anything away, so there\'s nothing to hide from unless you turn this on.'**
  String get offByDefaultTitleSSynopsis2;

  /// No description provided for @onByDefaultOtherPeopleS2.
  ///
  /// In en, this message translates to:
  /// **'on by default — other people\'s reviews say what they want, so each one stays softly covered until you tap it. Turn this off if you\'d rather just read them straight away.'**
  String get onByDefaultOtherPeopleS2;

  /// No description provided for @onceLinkedEveningsPlanTogetherShow2.
  ///
  /// In en, this message translates to:
  /// **'once linked, evenings you plan together show up on both of your co-viewing screens.'**
  String get onceLinkedEveningsPlanTogetherShow2;

  /// No description provided for @pastePublicYoutubeTwitchLinkSingle2.
  ///
  /// In en, this message translates to:
  /// **'paste a public YouTube or Twitch link — a single video, a whole playlist, a channel\'s uploads, or a Twitch channel\'s past broadcasts — and tanè will pull in what\'s there.'**
  String get pastePublicYoutubeTwitchLinkSingle2;

  /// No description provided for @privateListsLikeYoutubeSWatch2.
  ///
  /// In en, this message translates to:
  /// **'private lists like YouTube\'s Watch Later or Liked videos can\'t be reached this way — only things the link itself can actually see.'**
  String get privateListsLikeYoutubeSWatch2;

  /// No description provided for @showsTheseAlongsideMoviesShowsWatched2.
  ///
  /// In en, this message translates to:
  /// **'shows these alongside movies and shows in watched, watching, and plan to watch — heads up, they can look a little off there, since a source opens the video itself instead of a title page'**
  String get showsTheseAlongsideMoviesShowsWatched2;

  /// No description provided for @takePhotoWeLlPullTitle2.
  ///
  /// In en, this message translates to:
  /// **'take a photo of it and we\'ll pull the title off it, straight into search — from there it\'s one tap to plan to watch or watched, same as any other title.'**
  String get takePhotoWeLlPullTitle2;

  /// No description provided for @tanSOwnWordsStayEnglish2.
  ///
  /// In en, this message translates to:
  /// **'tanè\'s own words stay in English everywhere — this just decides whether title cards prefer Russian when there\'s a translation for them. change this anytime in settings.'**
  String get tanSOwnWordsStayEnglish2;

  /// No description provided for @theFlameCountsConsecutiveEveningsLeast2.
  ///
  /// In en, this message translates to:
  /// **'the flame counts consecutive evenings with at least one log — any diary entry keeps it going. today doesn\'t break it until it\'s over, so there\'s still time before it resets.'**
  String get theFlameCountsConsecutiveEveningsLeast2;

  /// No description provided for @thisSharedListSeparateFromOwn2.
  ///
  /// In en, this message translates to:
  /// **'this shared list is separate from your own \"plan to watch\" on Profile. Whether a match also lands there is up to you — see \"co-viewing\" in Settings.'**
  String get thisSharedListSeparateFromOwn2;

  /// No description provided for @typePasteAnyMixThemBelow2.
  ///
  /// In en, this message translates to:
  /// **'type or paste any mix of them below, one per line — tanè sorts out what\'s what and matches each to the right shelf.'**
  String get typePasteAnyMixThemBelow2;

  /// No description provided for @whenWatchTogetherMatchHappensOne2.
  ///
  /// In en, this message translates to:
  /// **'when a Watch Together match happens — one phone or over the network — it always shows up on your shared co-viewing screen if you have a partner linked. This only controls whether it also gets added to your own personal \"watch together\" list.'**
  String get whenWatchTogetherMatchHappensOne2;

  /// No description provided for @whichCountrySServicesShowUnder2.
  ///
  /// In en, this message translates to:
  /// **'which country\'s services show under \"where to watch\" — Kinopoisk, ivi, Netflix, and the rest all vary by country'**
  String get whichCountrySServicesShowUnder2;

  /// No description provided for @whichCountrySStreamingInfoTitle2.
  ///
  /// In en, this message translates to:
  /// **'which country\'s streaming info a title shows — change this anytime, it never touches what\'s already in your diary.'**
  String get whichCountrySStreamingInfoTitle2;

  /// No description provided for @yourEveningCalendar.
  ///
  /// In en, this message translates to:
  /// **'your evening, on the calendar'**
  String get yourEveningCalendar;

  /// No description provided for @yourLevelHereComesFromReal2.
  ///
  /// In en, this message translates to:
  /// **'your level here comes from real evenings — what you log, the notes you write, the streaks you keep. it\'s the same number on your profile\'s level ring, nothing extra to farm.'**
  String get yourLevelHereComesFromReal2;

  /// No description provided for @yourYoutubeTwitchSourcesWillShow2.
  ///
  /// In en, this message translates to:
  /// **'your YouTube and Twitch sources will show up alongside movies and shows in watched, watching, and plan to watch — heads up, they can look a little off there, since a source opens the video itself instead of a title page'**
  String get yourYoutubeTwitchSourcesWillShow2;

  /// No description provided for @broughtViaYoutubeTwitchLinksKept.
  ///
  /// In en, this message translates to:
  /// **'brought in via YouTube and Twitch links — kept separate from your movies and shows so it never skews those stats.'**
  String get broughtViaYoutubeTwitchLinksKept;

  /// No description provided for @wonTLoggedWayCanT.
  ///
  /// In en, this message translates to:
  /// **' won\'t be logged this way — this can\'t be undone.'**
  String get wonTLoggedWayCanT;

  /// No description provided for @tuckedAmongRestTonight.
  ///
  /// In en, this message translates to:
  /// **', tucked in among the rest · tonight'**
  String get tuckedAmongRestTonight;

  /// No description provided for @alreadyWatched.
  ///
  /// In en, this message translates to:
  /// **'already watched'**
  String get alreadyWatched;

  /// No description provided for @animeManga.
  ///
  /// In en, this message translates to:
  /// **'anime & manga'**
  String get animeManga;

  /// No description provided for @book.
  ///
  /// In en, this message translates to:
  /// **'book'**
  String get book;

  /// No description provided for @books.
  ///
  /// In en, this message translates to:
  /// **'books'**
  String get books;

  /// No description provided for @elapsed.
  ///
  /// In en, this message translates to:
  /// **'elapsed'**
  String get elapsed;

  /// No description provided for @filmRuns.
  ///
  /// In en, this message translates to:
  /// **'film runs'**
  String get filmRuns;

  /// No description provided for @from.
  ///
  /// In en, this message translates to:
  /// **'from'**
  String get from;

  /// No description provided for @game.
  ///
  /// In en, this message translates to:
  /// **'game'**
  String get game;

  /// No description provided for @games.
  ///
  /// In en, this message translates to:
  /// **'games'**
  String get games;

  /// No description provided for @hall.
  ///
  /// In en, this message translates to:
  /// **'HALL'**
  String get hall;

  /// No description provided for @inAir.
  ///
  /// In en, this message translates to:
  /// **'in the air'**
  String get inAir;

  /// No description provided for @keepsShelfPrivate.
  ///
  /// In en, this message translates to:
  /// **'keeps this shelf private'**
  String get keepsShelfPrivate;

  /// No description provided for @keepsTheirFavoritesPrivate.
  ///
  /// In en, this message translates to:
  /// **'keeps their favorites private'**
  String get keepsTheirFavoritesPrivate;

  /// No description provided for @hasnTPinnedAnyFavoriteFilms.
  ///
  /// In en, this message translates to:
  /// **'hasn\'t pinned any favorite films yet'**
  String get hasnTPinnedAnyFavoriteFilms;

  /// No description provided for @lastLogged.
  ///
  /// In en, this message translates to:
  /// **'last logged'**
  String get lastLogged;

  /// No description provided for @loggedWheneverActuallyHaveEveningNothing.
  ///
  /// In en, this message translates to:
  /// **'— logged whenever you actually have an evening, nothing to keep up with in between.'**
  String get loggedWheneverActuallyHaveEveningNothing;

  /// No description provided for @lastLeftOff.
  ///
  /// In en, this message translates to:
  /// **'last left off at'**
  String get lastLeftOff;

  /// No description provided for @left.
  ///
  /// In en, this message translates to:
  /// **'left'**
  String get left;

  /// No description provided for @longer.
  ///
  /// In en, this message translates to:
  /// **'longer'**
  String get longer;

  /// No description provided for @matched.
  ///
  /// In en, this message translates to:
  /// **'matched'**
  String get matched;

  /// No description provided for @minScreenTonight.
  ///
  /// In en, this message translates to:
  /// **'min on screen · tonight'**
  String get minScreenTonight;

  /// No description provided for @minRailsTonight.
  ///
  /// In en, this message translates to:
  /// **'min on the rails · tonight'**
  String get minRailsTonight;

  /// No description provided for @moviesTv.
  ///
  /// In en, this message translates to:
  /// **'movies & TV'**
  String get moviesTv;

  /// No description provided for @ofLabel.
  ///
  /// In en, this message translates to:
  /// **'of'**
  String get ofLabel;

  /// No description provided for @onRails.
  ///
  /// In en, this message translates to:
  /// **'on the rails'**
  String get onRails;

  /// No description provided for @outGarden.
  ///
  /// In en, this message translates to:
  /// **'out in the garden'**
  String get outGarden;

  /// No description provided for @planWatch.
  ///
  /// In en, this message translates to:
  /// **'plan to watch'**
  String get planWatch;

  /// No description provided for @rightAboutSameTime.
  ///
  /// In en, this message translates to:
  /// **'right about the same time'**
  String get rightAboutSameTime;

  /// No description provided for @rightWhereLeftOff.
  ///
  /// In en, this message translates to:
  /// **'right where it left off'**
  String get rightWhereLeftOff;

  /// No description provided for @runs.
  ///
  /// In en, this message translates to:
  /// **'runs'**
  String get runs;

  /// No description provided for @seat.
  ///
  /// In en, this message translates to:
  /// **'seat'**
  String get seat;

  /// No description provided for @shorter.
  ///
  /// In en, this message translates to:
  /// **'shorter'**
  String get shorter;

  /// No description provided for @skipNow.
  ///
  /// In en, this message translates to:
  /// **'skip for now'**
  String get skipNow;

  /// No description provided for @suggested2.
  ///
  /// In en, this message translates to:
  /// **'suggested this'**
  String get suggested2;

  /// No description provided for @theFlight.
  ///
  /// In en, this message translates to:
  /// **'the flight'**
  String get theFlight;

  /// No description provided for @theTrain.
  ///
  /// In en, this message translates to:
  /// **'the train'**
  String get theTrain;

  /// No description provided for @theWalk.
  ///
  /// In en, this message translates to:
  /// **'the walk'**
  String get theWalk;

  /// No description provided for @thenImportWhatLooksRight.
  ///
  /// In en, this message translates to:
  /// **'then import what looks right'**
  String get thenImportWhatLooksRight;

  /// No description provided for @toPickFrom.
  ///
  /// In en, this message translates to:
  /// **'to pick from'**
  String get toPickFrom;

  /// No description provided for @watched2.
  ///
  /// In en, this message translates to:
  /// **'watched with'**
  String get watched2;

  /// No description provided for @bloomedBed.
  ///
  /// In en, this message translates to:
  /// **'· bloomed in the bed'**
  String get bloomedBed;

  /// No description provided for @reviewBelow.
  ///
  /// In en, this message translates to:
  /// **'— review below, '**
  String get reviewBelow;

  /// No description provided for @amLieParasitePasteTraktExport.
  ///
  /// In en, this message translates to:
  /// **'Amélie\nParasite\n…or paste a Trakt export here'**
  String get amLieParasitePasteTraktExport;

  /// No description provided for @amLieParasitePasteImdbExport.
  ///
  /// In en, this message translates to:
  /// **'Amélie\nParasite\n…or paste an IMDb export here'**
  String get amLieParasitePasteImdbExport;

  /// No description provided for @amLie2001Parasite2019Bear.
  ///
  /// In en, this message translates to:
  /// **'Amélie (2001)\nParasite (2019)\nThe Bear\nElden Ring\nChainsaw Man\n…one title per line, any kind'**
  String get amLie2001Parasite2019Bear;

  /// No description provided for @amLie2001Parasite2019Paste.
  ///
  /// In en, this message translates to:
  /// **'Amélie (2001)\nParasite (2019)\n…or paste a Letterboxd export here'**
  String get amLie2001Parasite2019Paste;

  /// No description provided for @frierenVinlandSagaPasteMalExport.
  ///
  /// In en, this message translates to:
  /// **'Frieren\nVinland Saga\n…or paste a MAL export here'**
  String get frierenVinlandSagaPasteMalExport;

  /// No description provided for @frierenVinlandSagaPasteAnilistExport.
  ///
  /// In en, this message translates to:
  /// **'Frieren\nVinland Saga\n…or paste an AniList export here'**
  String get frierenVinlandSagaPasteAnilistExport;

  /// No description provided for @hadesOuterWildsPasteBackloggdExport.
  ///
  /// In en, this message translates to:
  /// **'Hades\nOuter Wilds\n…or paste a Backloggd export here'**
  String get hadesOuterWildsPasteBackloggdExport;

  /// No description provided for @hadesOuterWildsPasteTitlesFrom.
  ///
  /// In en, this message translates to:
  /// **'Hades\nOuter Wilds\n…paste titles from your list here'**
  String get hadesOuterWildsPasteTitlesFrom;

  /// No description provided for @myBooksImportExportExportLibrary.
  ///
  /// In en, this message translates to:
  /// **'My Books → Import/Export → Export Library, then open the CSV and paste the Title column below.'**
  String get myBooksImportExportExportLibrary;

  /// No description provided for @openListMenuExportCsvThen.
  ///
  /// In en, this message translates to:
  /// **'Open a list → the ⋯ menu → Export as CSV, then paste the titles column below.'**
  String get openListMenuExportCsvThen;

  /// No description provided for @panelListExportListThenOpen.
  ///
  /// In en, this message translates to:
  /// **'Panel → List → Export List, then open the file and paste the titles below.'**
  String get panelListExportListThenOpen;

  /// No description provided for @plexSettingsWebhooksAddWebhook.
  ///
  /// In en, this message translates to:
  /// **'Plex Settings → Webhooks → Add Webhook'**
  String get plexSettingsWebhooksAddWebhook;

  /// No description provided for @piranesiBellJarPasteGoodreadsExport.
  ///
  /// In en, this message translates to:
  /// **'Piranesi\nThe Bell Jar\n…or paste a Goodreads export here'**
  String get piranesiBellJarPasteGoodreadsExport;

  /// No description provided for @piranesiBellJarPasteStorygraphExport.
  ///
  /// In en, this message translates to:
  /// **'Piranesi\nThe Bell Jar\n…or paste a StoryGraph export here'**
  String get piranesiBellJarPasteStorygraphExport;

  /// No description provided for @settingsImportExportExportThenOpen.
  ///
  /// In en, this message translates to:
  /// **'Settings → Import & Export → Export, then open watched.csv (or watchlist.csv) and paste its contents below.'**
  String get settingsImportExportExportThenOpen;

  /// No description provided for @settingsImportExportExportDataThen.
  ///
  /// In en, this message translates to:
  /// **'Settings → Import/Export → Export Data, then paste the titles from your list below.'**
  String get settingsImportExportExportDataThen;

  /// No description provided for @settingsManageAccountExportStorygraphData.
  ///
  /// In en, this message translates to:
  /// **'Settings → Manage Your Account → Export StoryGraph Data, then paste the titles from the CSV below.'**
  String get settingsManageAccountExportStorygraphData;

  /// No description provided for @yourProfileGamesThenJustType.
  ///
  /// In en, this message translates to:
  /// **'Your profile → Games, then just type or paste the titles you see there below — HLTB doesn\'t offer a CSV export.'**
  String get yourProfileGamesThenJustType;

  /// No description provided for @yourProfileGamesListExportThen.
  ///
  /// In en, this message translates to:
  /// **'Your profile → the games list → Export, then paste the game titles below.'**
  String get yourProfileGamesListExportThen;

  /// No description provided for @yourRatingsPageExportWatchlistMenu.
  ///
  /// In en, this message translates to:
  /// **'Your Ratings page → Export (or a watchlist → the ⋯ menu → Export), then open the CSV and paste the Title column below.'**
  String get yourRatingsPageExportWatchlistMenu;

  /// No description provided for @couldnTUploadPhoto.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t upload photo'**
  String get couldnTUploadPhoto;

  /// No description provided for @episode.
  ///
  /// In en, this message translates to:
  /// **'episode'**
  String get episode;

  /// No description provided for @level.
  ///
  /// In en, this message translates to:
  /// **'level'**
  String get level;

  /// No description provided for @logged.
  ///
  /// In en, this message translates to:
  /// **'logged'**
  String get logged;

  /// No description provided for @season.
  ///
  /// In en, this message translates to:
  /// **'season'**
  String get season;

  /// No description provided for @toLevel.
  ///
  /// In en, this message translates to:
  /// **'to level'**
  String get toLevel;

  /// No description provided for @watch.
  ///
  /// In en, this message translates to:
  /// **'watch'**
  String get watch;

  /// No description provided for @anEmptyBoxWaiting.
  ///
  /// In en, this message translates to:
  /// **'an empty box, waiting'**
  String get anEmptyBoxWaiting;

  /// No description provided for @anEmptyMarqueeWaiting.
  ///
  /// In en, this message translates to:
  /// **'an empty marquee, waiting'**
  String get anEmptyMarqueeWaiting;

  /// No description provided for @anEmptyRoadWaiting.
  ///
  /// In en, this message translates to:
  /// **'an empty road, waiting'**
  String get anEmptyRoadWaiting;

  /// No description provided for @badgesEarned.
  ///
  /// In en, this message translates to:
  /// **'badges earned'**
  String get badgesEarned;

  /// No description provided for @badgesUnpinOneFirst.
  ///
  /// In en, this message translates to:
  /// **'badges — unpin one first'**
  String get badgesUnpinOneFirst;

  /// No description provided for @blooming.
  ///
  /// In en, this message translates to:
  /// **'blooming'**
  String get blooming;

  /// No description provided for @devoted.
  ///
  /// In en, this message translates to:
  /// **'devoted'**
  String get devoted;

  /// No description provided for @growing.
  ///
  /// In en, this message translates to:
  /// **'growing'**
  String get growing;

  /// No description provided for @grown.
  ///
  /// In en, this message translates to:
  /// **'grown'**
  String get grown;

  /// No description provided for @habit.
  ///
  /// In en, this message translates to:
  /// **'habit'**
  String get habit;

  /// No description provided for @hours.
  ///
  /// In en, this message translates to:
  /// **'hours in'**
  String get hours;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'import'**
  String get import;

  /// No description provided for @inLabel.
  ///
  /// In en, this message translates to:
  /// **'in'**
  String get inLabel;

  /// No description provided for @inRow.
  ///
  /// In en, this message translates to:
  /// **'in a row'**
  String get inRow;

  /// No description provided for @inProgress.
  ///
  /// In en, this message translates to:
  /// **'in progress'**
  String get inProgress;

  /// No description provided for @legend.
  ///
  /// In en, this message translates to:
  /// **'legend'**
  String get legend;

  /// No description provided for @newLabel.
  ///
  /// In en, this message translates to:
  /// **'new ›'**
  String get newLabel;

  /// No description provided for @noMatchesRound.
  ///
  /// In en, this message translates to:
  /// **'no matches this round'**
  String get noMatchesRound;

  /// No description provided for @nothingKeptRoundTryLooseningFilters.
  ///
  /// In en, this message translates to:
  /// **'nothing kept this round — try loosening the filters'**
  String get nothingKeptRoundTryLooseningFilters;

  /// No description provided for @nothingMatchesCombination.
  ///
  /// In en, this message translates to:
  /// **'nothing matches that combination'**
  String get nothingMatchesCombination;

  /// No description provided for @nothingPlantedYet.
  ///
  /// In en, this message translates to:
  /// **'nothing planted yet'**
  String get nothingPlantedYet;

  /// No description provided for @nothingSelected.
  ///
  /// In en, this message translates to:
  /// **'nothing selected'**
  String get nothingSelected;

  /// No description provided for @obsession.
  ///
  /// In en, this message translates to:
  /// **'obsession'**
  String get obsession;

  /// No description provided for @onRoad.
  ///
  /// In en, this message translates to:
  /// **'on the road'**
  String get onRoad;

  /// No description provided for @running.
  ///
  /// In en, this message translates to:
  /// **'running'**
  String get running;

  /// No description provided for @seat2.
  ///
  /// In en, this message translates to:
  /// **'SEAT'**
  String get seat2;

  /// No description provided for @skipped.
  ///
  /// In en, this message translates to:
  /// **'skipped'**
  String get skipped;

  /// No description provided for @soFar.
  ///
  /// In en, this message translates to:
  /// **'so far'**
  String get soFar;

  /// No description provided for @they.
  ///
  /// In en, this message translates to:
  /// **'they'**
  String get they;

  /// No description provided for @toChooseFrom.
  ///
  /// In en, this message translates to:
  /// **'to choose from'**
  String get toChooseFrom;

  /// No description provided for @upMarquee.
  ///
  /// In en, this message translates to:
  /// **'up on the marquee'**
  String get upMarquee;

  /// No description provided for @waiting.
  ///
  /// In en, this message translates to:
  /// **'waiting'**
  String get waiting;

  /// No description provided for @youCanShowcaseUp.
  ///
  /// In en, this message translates to:
  /// **'you can showcase up to'**
  String get youCanShowcaseUp;

  /// No description provided for @aLittleCinemaTicketTornEach.
  ///
  /// In en, this message translates to:
  /// **'a little cinema, ticket torn for each evening'**
  String get aLittleCinemaTicketTornEach;

  /// No description provided for @aMediaCenterAppTvBox.
  ///
  /// In en, this message translates to:
  /// **'a media-center app on a TV box, PC, or console'**
  String get aMediaCenterAppTvBox;

  /// No description provided for @aTicketTornOpen.
  ///
  /// In en, this message translates to:
  /// **'a ticket, torn open'**
  String get aTicketTornOpen;

  /// No description provided for @aWindowGardenFlowerGrownEach.
  ///
  /// In en, this message translates to:
  /// **'a window garden, a flower grown for each evening'**
  String get aWindowGardenFlowerGrownEach;

  /// No description provided for @aWindowGardenBloom.
  ///
  /// In en, this message translates to:
  /// **'a window garden, in bloom'**
  String get aWindowGardenBloom;

  /// No description provided for @acceptInvite.
  ///
  /// In en, this message translates to:
  /// **'accept invite'**
  String get acceptInvite;

  /// No description provided for @acceptRequest.
  ///
  /// In en, this message translates to:
  /// **'accept request'**
  String get acceptRequest;

  /// No description provided for @addFriend.
  ///
  /// In en, this message translates to:
  /// **'add friend'**
  String get addFriend;

  /// No description provided for @afternoon.
  ///
  /// In en, this message translates to:
  /// **'afternoon'**
  String get afternoon;

  /// No description provided for @anEveningRouteBoardedTornGate.
  ///
  /// In en, this message translates to:
  /// **'an evening route, boarded and torn at the gate'**
  String get anEveningRouteBoardedTornGate;

  /// No description provided for @anEveningRouteByTrain.
  ///
  /// In en, this message translates to:
  /// **'an evening route, by train'**
  String get anEveningRouteByTrain;

  /// No description provided for @bringOverListFromLetterboxdElsewhere.
  ///
  /// In en, this message translates to:
  /// **'bring over a list from Letterboxd or elsewhere'**
  String get bringOverListFromLetterboxdElsewhere;

  /// No description provided for @ch.
  ///
  /// In en, this message translates to:
  /// **'ch.'**
  String get ch;

  /// No description provided for @check.
  ///
  /// In en, this message translates to:
  /// **'check in'**
  String get check;

  /// No description provided for @confirmBoarding.
  ///
  /// In en, this message translates to:
  /// **'confirm boarding'**
  String get confirmBoarding;

  /// No description provided for @confirmSeat.
  ///
  /// In en, this message translates to:
  /// **'confirm seat'**
  String get confirmSeat;

  /// No description provided for @confirmPlanting.
  ///
  /// In en, this message translates to:
  /// **'confirm planting'**
  String get confirmPlanting;

  /// No description provided for @confirmTicket.
  ///
  /// In en, this message translates to:
  /// **'confirm ticket'**
  String get confirmTicket;

  /// No description provided for @createMyDiary.
  ///
  /// In en, this message translates to:
  /// **'create my diary'**
  String get createMyDiary;

  /// No description provided for @developer.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get developer;

  /// No description provided for @discover.
  ///
  /// In en, this message translates to:
  /// **'discover'**
  String get discover;

  /// No description provided for @doesnTMatterAnyGenre.
  ///
  /// In en, this message translates to:
  /// **'doesn\'t matter — any genre'**
  String get doesnTMatterAnyGenre;

  /// No description provided for @doesnTMatterAnyType.
  ///
  /// In en, this message translates to:
  /// **'doesn\'t matter — any type'**
  String get doesnTMatterAnyType;

  /// No description provided for @doesnTMatterAnyYear.
  ///
  /// In en, this message translates to:
  /// **'doesn\'t matter — any year'**
  String get doesnTMatterAnyYear;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'done'**
  String get done;

  /// No description provided for @evening.
  ///
  /// In en, this message translates to:
  /// **'evening'**
  String get evening;

  /// No description provided for @favoriteFilms.
  ///
  /// In en, this message translates to:
  /// **'favorite films'**
  String get favoriteFilms;

  /// No description provided for @gameEvening.
  ///
  /// In en, this message translates to:
  /// **'game of the evening'**
  String get gameEvening;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'home'**
  String get home;

  /// No description provided for @inCircle.
  ///
  /// In en, this message translates to:
  /// **'in your circle'**
  String get inCircle;

  /// No description provided for @inviteSent.
  ///
  /// In en, this message translates to:
  /// **'invite sent'**
  String get inviteSent;

  /// No description provided for @inviteCoViewing.
  ///
  /// In en, this message translates to:
  /// **'invite to co-viewing'**
  String get inviteCoViewing;

  /// No description provided for @isbn.
  ///
  /// In en, this message translates to:
  /// **'ISBN'**
  String get isbn;

  /// No description provided for @itSYours.
  ///
  /// In en, this message translates to:
  /// **'it\'s yours'**
  String get itSYours;

  /// No description provided for @itSBestEffortScraperNot.
  ///
  /// In en, this message translates to:
  /// **'it\'s a best-effort scraper, not an official API — if a watch stops showing up for one service, that one may need a small fix'**
  String get itSBestEffortScraperNot;

  /// No description provided for @join.
  ///
  /// In en, this message translates to:
  /// **'join'**
  String get join;

  /// No description provided for @keepStub.
  ///
  /// In en, this message translates to:
  /// **'keep the stub'**
  String get keepStub;

  /// No description provided for @leaveGrowing.
  ///
  /// In en, this message translates to:
  /// **'leave it growing'**
  String get leaveGrowing;

  /// No description provided for @length.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get length;

  /// No description provided for @loggingRitual.
  ///
  /// In en, this message translates to:
  /// **'logging ritual'**
  String get loggingRitual;

  /// No description provided for @min.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get min;

  /// No description provided for @modes.
  ///
  /// In en, this message translates to:
  /// **'Modes'**
  String get modes;

  /// No description provided for @morning.
  ///
  /// In en, this message translates to:
  /// **'morning'**
  String get morning;

  /// No description provided for @night.
  ///
  /// In en, this message translates to:
  /// **'night'**
  String get night;

  /// No description provided for @notRated.
  ///
  /// In en, this message translates to:
  /// **'not rated'**
  String get notRated;

  /// No description provided for @notTonight.
  ///
  /// In en, this message translates to:
  /// **'not tonight'**
  String get notTonight;

  /// No description provided for @onePhone.
  ///
  /// In en, this message translates to:
  /// **'one phone'**
  String get onePhone;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'open'**
  String get open;

  /// No description provided for @openPlanWatch.
  ///
  /// In en, this message translates to:
  /// **'open plan to watch'**
  String get openPlanWatch;

  /// No description provided for @openList.
  ///
  /// In en, this message translates to:
  /// **'open the list'**
  String get openList;

  /// No description provided for @overNetwork.
  ///
  /// In en, this message translates to:
  /// **'over the network'**
  String get overNetwork;

  /// No description provided for @pickedTonight.
  ///
  /// In en, this message translates to:
  /// **'picked for tonight'**
  String get pickedTonight;

  /// No description provided for @platforms.
  ///
  /// In en, this message translates to:
  /// **'Platforms'**
  String get platforms;

  /// No description provided for @plexJellyfinKodiBrowserExtension.
  ///
  /// In en, this message translates to:
  /// **'Plex, Jellyfin, Kodi, browser extension'**
  String get plexJellyfinKodiBrowserExtension;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'profile'**
  String get profile;

  /// No description provided for @publisher.
  ///
  /// In en, this message translates to:
  /// **'Publisher'**
  String get publisher;

  /// No description provided for @pullApartGetTicket.
  ///
  /// In en, this message translates to:
  /// **'pull apart to get your ticket'**
  String get pullApartGetTicket;

  /// No description provided for @pullApartTearUp.
  ///
  /// In en, this message translates to:
  /// **'pull apart to tear it up'**
  String get pullApartTearUp;

  /// No description provided for @remaining.
  ///
  /// In en, this message translates to:
  /// **'remaining'**
  String get remaining;

  /// No description provided for @reroll.
  ///
  /// In en, this message translates to:
  /// **'reroll'**
  String get reroll;

  /// No description provided for @sign.
  ///
  /// In en, this message translates to:
  /// **'sign in'**
  String get sign;

  /// No description provided for @soon.
  ///
  /// In en, this message translates to:
  /// **'soon'**
  String get soon;

  /// No description provided for @spinAgain.
  ///
  /// In en, this message translates to:
  /// **'spin again'**
  String get spinAgain;

  /// No description provided for @startSession.
  ///
  /// In en, this message translates to:
  /// **'start a session'**
  String get startSession;

  /// No description provided for @startSwiping.
  ///
  /// In en, this message translates to:
  /// **'start swiping'**
  String get startSwiping;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @swipeAgain.
  ///
  /// In en, this message translates to:
  /// **'swipe again'**
  String get swipeAgain;

  /// No description provided for @theSynopsisMightGiveThingsAway.
  ///
  /// In en, this message translates to:
  /// **'the synopsis might give things away'**
  String get theSynopsisMightGiveThingsAway;

  /// No description provided for @thisReviewMightSpoil.
  ///
  /// In en, this message translates to:
  /// **'this review might spoil it'**
  String get thisReviewMightSpoil;

  /// No description provided for @thisWeekend.
  ///
  /// In en, this message translates to:
  /// **'this weekend'**
  String get thisWeekend;

  /// No description provided for @to.
  ///
  /// In en, this message translates to:
  /// **'to'**
  String get to;

  /// No description provided for @torn.
  ///
  /// In en, this message translates to:
  /// **'torn'**
  String get torn;

  /// No description provided for @vol.
  ///
  /// In en, this message translates to:
  /// **'vol.'**
  String get vol;

  /// No description provided for @watchingNow.
  ///
  /// In en, this message translates to:
  /// **'watching now'**
  String get watchingNow;

  /// No description provided for @newEpisodesHome.
  ///
  /// In en, this message translates to:
  /// **'new episodes'**
  String get newEpisodesHome;

  /// No description provided for @releaseCalendarHome.
  ///
  /// In en, this message translates to:
  /// **'release calendar'**
  String get releaseCalendarHome;

  /// No description provided for @justOutBadge.
  ///
  /// In en, this message translates to:
  /// **'just out'**
  String get justOutBadge;

  /// No description provided for @nextUpRelease.
  ///
  /// In en, this message translates to:
  /// **'next up'**
  String get nextUpRelease;

  /// No description provided for @withLabel.
  ///
  /// In en, this message translates to:
  /// **'with'**
  String get withLabel;

  /// No description provided for @youFriendRunOneTheseStore.
  ///
  /// In en, this message translates to:
  /// **'you (or a friend) run one of these to store and stream your own library'**
  String get youFriendRunOneTheseStore;

  /// No description provided for @youJustWatchThingsStreamingSites.
  ///
  /// In en, this message translates to:
  /// **'you just watch things on streaming sites like Netflix or Kinopoisk in a normal browser'**
  String get youJustWatchThingsStreamingSites;

  /// No description provided for @anime.
  ///
  /// In en, this message translates to:
  /// **'anime'**
  String get anime;

  /// No description provided for @eveningsCinemaRewatchesClassics.
  ///
  /// In en, this message translates to:
  /// **'evenings at the cinema, rewatches, the classics'**
  String get eveningsCinemaRewatchesClassics;

  /// No description provided for @manga.
  ///
  /// In en, this message translates to:
  /// **'manga'**
  String get manga;

  /// No description provided for @movie.
  ///
  /// In en, this message translates to:
  /// **'movie'**
  String get movie;

  /// No description provided for @movies.
  ///
  /// In en, this message translates to:
  /// **'movies'**
  String get movies;

  /// No description provided for @seasonBySeasonWhateverSAiring.
  ///
  /// In en, this message translates to:
  /// **'season by season, whatever\'s airing tonight'**
  String get seasonBySeasonWhateverSAiring;

  /// No description provided for @series.
  ///
  /// In en, this message translates to:
  /// **'series'**
  String get series;

  /// No description provided for @showsReMarathoningNewEpisodesThey.
  ///
  /// In en, this message translates to:
  /// **'shows you\'re marathoning, new episodes as they land'**
  String get showsReMarathoningNewEpisodesThey;

  /// No description provided for @volumesChaptersOneTime.
  ///
  /// In en, this message translates to:
  /// **'volumes and chapters, one at a time'**
  String get volumesChaptersOneTime;

  /// No description provided for @whatRePlayingAboutStart.
  ///
  /// In en, this message translates to:
  /// **'what you\'re playing, or about to start'**
  String get whatRePlayingAboutStart;

  /// No description provided for @whateverReReadingPageByPage.
  ///
  /// In en, this message translates to:
  /// **'whatever you\'re reading, page by page'**
  String get whateverReReadingPageByPage;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'create'**
  String get create;

  /// No description provided for @yourDiaryBecomesBoardJourneysTaken.
  ///
  /// In en, this message translates to:
  /// **'your diary becomes a board of journeys taken'**
  String get yourDiaryBecomesBoardJourneysTaken;

  /// No description provided for @yourDiaryBecomesGardenFillingOver.
  ///
  /// In en, this message translates to:
  /// **'your diary becomes a garden, filling in over time'**
  String get yourDiaryBecomesGardenFillingOver;

  /// No description provided for @yourDiaryBecomesJarFillingUp.
  ///
  /// In en, this message translates to:
  /// **'your diary becomes a jar, filling up with stubs'**
  String get yourDiaryBecomesJarFillingUp;

  /// No description provided for @aMovieLikeInterstellar.
  ///
  /// In en, this message translates to:
  /// **'a movie like Interstellar'**
  String get aMovieLikeInterstellar;

  /// No description provided for @aNostalgic90sPick.
  ///
  /// In en, this message translates to:
  /// **'a nostalgic 90s pick'**
  String get aNostalgic90sPick;

  /// No description provided for @aTwistyWhodunit.
  ///
  /// In en, this message translates to:
  /// **'a twisty whodunit'**
  String get aTwistyWhodunit;

  /// No description provided for @cozyComedySeries.
  ///
  /// In en, this message translates to:
  /// **'cozy comedy series'**
  String get cozyComedySeries;

  /// No description provided for @highFantasyBigWorld.
  ///
  /// In en, this message translates to:
  /// **'high-fantasy, big world'**
  String get highFantasyBigWorld;

  /// No description provided for @justSpookyEnough.
  ///
  /// In en, this message translates to:
  /// **'just spooky enough'**
  String get justSpookyEnough;

  /// No description provided for @mindlessPopcornAction.
  ///
  /// In en, this message translates to:
  /// **'mindless popcorn action'**
  String get mindlessPopcornAction;

  /// No description provided for @narrowDownFirst.
  ///
  /// In en, this message translates to:
  /// **'narrow it down first'**
  String get narrowDownFirst;

  /// No description provided for @nice.
  ///
  /// In en, this message translates to:
  /// **'nice'**
  String get nice;

  /// No description provided for @notOne.
  ///
  /// In en, this message translates to:
  /// **'not this one'**
  String get notOne;

  /// No description provided for @rainyDayNoThinkingRequired.
  ///
  /// In en, this message translates to:
  /// **'rainy day, no thinking required'**
  String get rainyDayNoThinkingRequired;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'search'**
  String get search;

  /// No description provided for @slowBurnSliceLife.
  ///
  /// In en, this message translates to:
  /// **'slow-burn slice of life'**
  String get slowBurnSliceLife;

  /// No description provided for @somethingLlMakeMeCry.
  ///
  /// In en, this message translates to:
  /// **'something that\'ll make me cry'**
  String get somethingLlMakeMeCry;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'take a photo'**
  String get takePhoto;

  /// No description provided for @thatDoesnTTakeItselfToo.
  ///
  /// In en, this message translates to:
  /// **'that doesn\'t take itself too seriously'**
  String get thatDoesnTTakeItselfToo;

  /// No description provided for @throughGate.
  ///
  /// In en, this message translates to:
  /// **'through the gate'**
  String get throughGate;

  /// No description provided for @takeMeMyShelf.
  ///
  /// In en, this message translates to:
  /// **'take me to my shelf'**
  String get takeMeMyShelf;

  /// No description provided for @thisUpdatesMomentTheyCatchUp.
  ///
  /// In en, this message translates to:
  /// **'this updates the moment they catch up.'**
  String get thisUpdatesMomentTheyCatchUp;

  /// No description provided for @voteAgain.
  ///
  /// In en, this message translates to:
  /// **'vote again'**
  String get voteAgain;

  /// No description provided for @waitingOthersFinishVoting.
  ///
  /// In en, this message translates to:
  /// **'waiting on the others to finish voting'**
  String get waitingOthersFinishVoting;

  /// No description provided for @waitingThemFinishVoting.
  ///
  /// In en, this message translates to:
  /// **'waiting on them to finish voting'**
  String get waitingThemFinishVoting;

  /// No description provided for @writeOwn.
  ///
  /// In en, this message translates to:
  /// **'write your own…'**
  String get writeOwn;

  /// No description provided for @yes2.
  ///
  /// In en, this message translates to:
  /// **'yes, this'**
  String get yes2;

  /// No description provided for @classic.
  ///
  /// In en, this message translates to:
  /// **'classic'**
  String get classic;

  /// No description provided for @paper.
  ///
  /// In en, this message translates to:
  /// **'paper'**
  String get paper;

  /// No description provided for @terrain.
  ///
  /// In en, this message translates to:
  /// **'terrain'**
  String get terrain;

  /// No description provided for @open2.
  ///
  /// In en, this message translates to:
  /// **'open it'**
  String get open2;

  /// No description provided for @proposeCircle.
  ///
  /// In en, this message translates to:
  /// **'propose it to the circle'**
  String get proposeCircle;

  /// No description provided for @shareCard.
  ///
  /// In en, this message translates to:
  /// **'share the card'**
  String get shareCard;

  /// No description provided for @topGenre.
  ///
  /// In en, this message translates to:
  /// **'top genre'**
  String get topGenre;

  /// No description provided for @aShortlistCountdownMostVotesWins.
  ///
  /// In en, this message translates to:
  /// **'a shortlist, a countdown, most votes wins'**
  String get aShortlistCountdownMostVotesWins;

  /// No description provided for @added.
  ///
  /// In en, this message translates to:
  /// **'added'**
  String get added;

  /// No description provided for @addingTheseDiary.
  ///
  /// In en, this message translates to:
  /// **'adding these to your diary…'**
  String get addingTheseDiary;

  /// No description provided for @addingTheseSources.
  ///
  /// In en, this message translates to:
  /// **'adding these to your sources…'**
  String get addingTheseSources;

  /// No description provided for @alwaysAvailable.
  ///
  /// In en, this message translates to:
  /// **'always available'**
  String get alwaysAvailable;

  /// No description provided for @and.
  ///
  /// In en, this message translates to:
  /// **'and'**
  String get and;

  /// No description provided for @checkCameraPermissionDeviceSettingsTry.
  ///
  /// In en, this message translates to:
  /// **'check the camera permission in your device settings and try again'**
  String get checkCameraPermissionDeviceSettingsTry;

  /// No description provided for @checkConnectionTryAgain.
  ///
  /// In en, this message translates to:
  /// **'check the connection and try again'**
  String get checkConnectionTryAgain;

  /// No description provided for @chooseWorld.
  ///
  /// In en, this message translates to:
  /// **'choose this world'**
  String get chooseWorld;

  /// No description provided for @collectionsLeadsWhateverReIntoFrom.
  ///
  /// In en, this message translates to:
  /// **'collections leads with whatever you\'re into, from day one — change what it leads with anytime.'**
  String get collectionsLeadsWhateverReIntoFrom;

  /// No description provided for @continueWatching.
  ///
  /// In en, this message translates to:
  /// **'continue watching'**
  String get continueWatching;

  /// No description provided for @couldnTGatherAnyCards.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t gather any cards'**
  String get couldnTGatherAnyCards;

  /// No description provided for @couldnTMakeOutAnyText.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t make out any text on that'**
  String get couldnTMakeOutAnyText;

  /// No description provided for @couldnTOpenCamera.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t open the camera'**
  String get couldnTOpenCamera;

  /// No description provided for @couldnTStartSession.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t start a session'**
  String get couldnTStartSession;

  /// No description provided for @couldnTReachTanSCatalog.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t reach tanè\'s catalog just now'**
  String get couldnTReachTanSCatalog;

  /// No description provided for @couldnTFindAnythingThereCheck.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t find anything there — check it\'s public and try again'**
  String get couldnTFindAnythingThereCheck;

  /// No description provided for @couldnTResolveLinkJustNow.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t resolve that link just now — try again in a moment'**
  String get couldnTResolveLinkJustNow;

  /// No description provided for @couldnTReachServerCheckS.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t reach the server — check it\'s running and reachable'**
  String get couldnTReachServerCheckS;

  /// No description provided for @describeEveningProposePick.
  ///
  /// In en, this message translates to:
  /// **'describe the evening, propose the pick'**
  String get describeEveningProposePick;

  /// No description provided for @eachOwnPhoneSharedCodeSwiping.
  ///
  /// In en, this message translates to:
  /// **'Each on your own phone with a shared code, swiping blind. Only a title you both separately say yes to becomes a match.'**
  String get eachOwnPhoneSharedCodeSwiping;

  /// No description provided for @eitherCanTapWatchedOnceVe.
  ///
  /// In en, this message translates to:
  /// **'Either of you can tap \"watched\" once you\'ve actually seen it — that logs the evening into both your diaries at once.'**
  String get eitherCanTapWatchedOnceVe;

  /// No description provided for @everyoneSwipesMatchWins.
  ///
  /// In en, this message translates to:
  /// **'everyone swipes, a match wins'**
  String get everyoneSwipesMatchWins;

  /// No description provided for @fetchLink.
  ///
  /// In en, this message translates to:
  /// **'fetch link'**
  String get fetchLink;

  /// No description provided for @fetchingWhatSLink.
  ///
  /// In en, this message translates to:
  /// **'fetching what\'s at that link…'**
  String get fetchingWhatSLink;

  /// No description provided for @forLabel.
  ///
  /// In en, this message translates to:
  /// **'for you'**
  String get forLabel;

  /// No description provided for @forTrailers.
  ///
  /// In en, this message translates to:
  /// **'for you, with trailers'**
  String get forTrailers;

  /// No description provided for @freshDiary.
  ///
  /// In en, this message translates to:
  /// **'fresh in your diary'**
  String get freshDiary;

  /// No description provided for @homeLearnsFromWhatVeWatched.
  ///
  /// In en, this message translates to:
  /// **'home learns from what you\'ve watched and loved, and ask tanè helps when you can\'t decide.'**
  String get homeLearnsFromWhatVeWatched;

  /// No description provided for @leftSkipRightPlanWatch.
  ///
  /// In en, this message translates to:
  /// **'left to skip, right for plan to watch'**
  String get leftSkipRightPlanWatch;

  /// No description provided for @letSGo.
  ///
  /// In en, this message translates to:
  /// **'let\'s go'**
  String get letSGo;

  /// No description provided for @logEveningWay.
  ///
  /// In en, this message translates to:
  /// **'log an evening, your way'**
  String get logEveningWay;

  /// No description provided for @longestStreak.
  ///
  /// In en, this message translates to:
  /// **'longest streak'**
  String get longestStreak;

  /// No description provided for @lookingTheseUpCatalog.
  ///
  /// In en, this message translates to:
  /// **'looking these up in the catalog…'**
  String get lookingTheseUpCatalog;

  /// No description provided for @markWatched.
  ///
  /// In en, this message translates to:
  /// **'mark it watched'**
  String get markWatched;

  /// No description provided for @markedWatched.
  ///
  /// In en, this message translates to:
  /// **'marked as watched'**
  String get markedWatched;

  /// No description provided for @moreTonight.
  ///
  /// In en, this message translates to:
  /// **'more for tonight'**
  String get moreTonight;

  /// No description provided for @moviesShowsBooksGamesMangaOne.
  ///
  /// In en, this message translates to:
  /// **'movies, shows, books, games, manga — one diary for all of it, with a little ritual to close it out.'**
  String get moviesShowsBooksGamesMangaOne;

  /// No description provided for @noMatchRoundTryAgainJust.
  ///
  /// In en, this message translates to:
  /// **'no match this round — try again, or just pick for us.'**
  String get noMatchRoundTryAgainJust;

  /// No description provided for @nothingThereVoteYet.
  ///
  /// In en, this message translates to:
  /// **'nothing there to vote on yet'**
  String get nothingThereVoteYet;

  /// No description provided for @nothingShuffleRightNow.
  ///
  /// In en, this message translates to:
  /// **'nothing to shuffle right now'**
  String get nothingShuffleRightNow;

  /// No description provided for @nothingWasAdded.
  ///
  /// In en, this message translates to:
  /// **'nothing was added'**
  String get nothingWasAdded;

  /// No description provided for @oneTapFromTitlePageSends.
  ///
  /// In en, this message translates to:
  /// **'One tap from a title page sends it to your partner\'s Home card, or the \"suggested\" tab here. It only lands in \"planned\" once they accept — ✕ declines it for good.'**
  String get oneTapFromTitlePageSends;

  /// No description provided for @oneTitleDrawnFromPool.
  ///
  /// In en, this message translates to:
  /// **'one title, drawn from the pool'**
  String get oneTitleDrawnFromPool;

  /// No description provided for @oneTitlePulledFromPoolAbove.
  ///
  /// In en, this message translates to:
  /// **'one title, pulled from the pool above'**
  String get oneTitlePulledFromPoolAbove;

  /// No description provided for @pairUpPartnerFriendsVoteWhat.
  ///
  /// In en, this message translates to:
  /// **'pair up with a partner or friends, vote on what\'s next, and keep a shared thread of evenings.'**
  String get pairUpPartnerFriendsVoteWhat;

  /// No description provided for @passingPhoneBackForthOneSwipe.
  ///
  /// In en, this message translates to:
  /// **'Passing the phone back and forth, one swipe is already both your yes — no second turn needed. It lands in \"planned\" the moment you decide.'**
  String get passingPhoneBackForthOneSwipe;

  /// No description provided for @pickSomethingFromShelf.
  ///
  /// In en, this message translates to:
  /// **'pick something from your shelf'**
  String get pickSomethingFromShelf;

  /// No description provided for @picked.
  ///
  /// In en, this message translates to:
  /// **'picked for you'**
  String get picked;

  /// No description provided for @rateLogEveningNow.
  ///
  /// In en, this message translates to:
  /// **'rate it and log the evening now'**
  String get rateLogEveningNow;

  /// No description provided for @readingTicket.
  ///
  /// In en, this message translates to:
  /// **'reading your ticket…'**
  String get readingTicket;

  /// No description provided for @requestSent.
  ///
  /// In en, this message translates to:
  /// **'request sent'**
  String get requestSent;

  /// No description provided for @seeAll3.
  ///
  /// In en, this message translates to:
  /// **'see all →'**
  String get seeAll3;

  /// No description provided for @shelvesBuiltAround.
  ///
  /// In en, this message translates to:
  /// **'shelves built around you'**
  String get shelvesBuiltAround;

  /// No description provided for @something.
  ///
  /// In en, this message translates to:
  /// **'something'**
  String get something;

  /// No description provided for @somethingTonight.
  ///
  /// In en, this message translates to:
  /// **'something for tonight'**
  String get somethingTonight;

  /// No description provided for @somethingMakeMeCry.
  ///
  /// In en, this message translates to:
  /// **'something to make me cry'**
  String get somethingMakeMeCry;

  /// No description provided for @somethingWentWrongPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'something went wrong — please try again'**
  String get somethingWentWrongPleaseTryAgain;

  /// No description provided for @suggestThenTheyAgree.
  ///
  /// In en, this message translates to:
  /// **'suggest, then they agree'**
  String get suggestThenTheyAgree;

  /// No description provided for @tellWhatKindEveningReAfter.
  ///
  /// In en, this message translates to:
  /// **'tell it what kind of evening you\'re after'**
  String get tellWhatKindEveningReAfter;

  /// No description provided for @toList.
  ///
  /// In en, this message translates to:
  /// **'to your list'**
  String get toList;

  /// No description provided for @tryDifferentCategoryCheckBackLater.
  ///
  /// In en, this message translates to:
  /// **'try a different category, or check back later'**
  String get tryDifferentCategoryCheckBackLater;

  /// No description provided for @tryAgainBetterLightHoldFlatter.
  ///
  /// In en, this message translates to:
  /// **'try again with better light, or hold it flatter to the camera'**
  String get tryAgainBetterLightHoldFlatter;

  /// No description provided for @wantsFriends.
  ///
  /// In en, this message translates to:
  /// **'wants to be friends'**
  String get wantsFriends;

  /// No description provided for @watchRollLandSomething.
  ///
  /// In en, this message translates to:
  /// **'watch it roll and land on something'**
  String get watchRollLandSomething;

  /// No description provided for @watchTogether2.
  ///
  /// In en, this message translates to:
  /// **'watch it together'**
  String get watchTogether2;

  /// No description provided for @watchTogetherOnePhone.
  ///
  /// In en, this message translates to:
  /// **'watch together — one phone'**
  String get watchTogetherOnePhone;

  /// No description provided for @watchTogetherOverNetwork.
  ///
  /// In en, this message translates to:
  /// **'watch together — over the network'**
  String get watchTogetherOverNetwork;

  /// No description provided for @watching.
  ///
  /// In en, this message translates to:
  /// **'watching'**
  String get watching;

  /// No description provided for @whenTitleHasOne.
  ///
  /// In en, this message translates to:
  /// **'when a title has one'**
  String get whenTitleHasOne;

  /// No description provided for @couldnTLoadCatalogJustNow.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load the catalog just now — try again in a moment'**
  String get couldnTLoadCatalogJustNow;

  /// No description provided for @directedBy.
  ///
  /// In en, this message translates to:
  /// **'directed by'**
  String get directedBy;

  /// No description provided for @nothingPlannedTogetherYetSuggestFew.
  ///
  /// In en, this message translates to:
  /// **'nothing planned together yet — suggest a few titles first'**
  String get nothingPlannedTogetherYetSuggestFew;

  /// No description provided for @nothingQueuedEitherSideYetAdd.
  ///
  /// In en, this message translates to:
  /// **'nothing queued on either side yet — add a few titles to your plan-to-watch shelves first'**
  String get nothingQueuedEitherSideYetAdd;

  /// No description provided for @nothingQueuedEitherSideYetAdd2.
  ///
  /// In en, this message translates to:
  /// **'nothing queued on either side yet — add a few titles, or plan something together first'**
  String get nothingQueuedEitherSideYetAdd2;

  /// No description provided for @nothingSuggestedYetWhen.
  ///
  /// In en, this message translates to:
  /// **'nothing suggested yet — when'**
  String get nothingSuggestedYetWhen;

  /// No description provided for @pleaseFastenSeatbeltWeRePulling.
  ///
  /// In en, this message translates to:
  /// **'please fasten your seatbelt — we\'re pulling out shortly'**
  String get pleaseFastenSeatbeltWeRePulling;

  /// No description provided for @pleaseSilencePhoneShowAboutStart.
  ///
  /// In en, this message translates to:
  /// **'please silence your phone — the show is about to start'**
  String get pleaseSilencePhoneShowAboutStart;

  /// No description provided for @someoneCircle.
  ///
  /// In en, this message translates to:
  /// **'someone in your circle'**
  String get someoneCircle;

  /// No description provided for @suggestsTitleFromAnyTitlePage.
  ///
  /// In en, this message translates to:
  /// **'suggests a title from any title page, it shows up here.'**
  String get suggestsTitleFromAnyTitlePage;

  /// No description provided for @theBirdsHaveGoneQuietNight.
  ///
  /// In en, this message translates to:
  /// **'the birds have gone quiet for the night'**
  String get theBirdsHaveGoneQuietNight;

  /// No description provided for @unlocked.
  ///
  /// In en, this message translates to:
  /// **'unlocked'**
  String get unlocked;

  /// No description provided for @yourPartner.
  ///
  /// In en, this message translates to:
  /// **'your partner'**
  String get yourPartner;

  /// No description provided for @back2.
  ///
  /// In en, this message translates to:
  /// **'back to'**
  String get back2;

  /// No description provided for @comesOffTicketCanAlwaysPlan.
  ///
  /// In en, this message translates to:
  /// **'comes off your ticket — you can always plan another evening.'**
  String get comesOffTicketCanAlwaysPlan;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'copied'**
  String get copied;

  /// No description provided for @everyFriendWhoJoinsCodeEarns.
  ///
  /// In en, this message translates to:
  /// **'every friend who joins with your code earns you'**
  String get everyFriendWhoJoinsCodeEarns;

  /// No description provided for @match.
  ///
  /// In en, this message translates to:
  /// **'match'**
  String get match;

  /// No description provided for @morePlanned.
  ///
  /// In en, this message translates to:
  /// **'more planned'**
  String get morePlanned;

  /// No description provided for @nothingStreaming.
  ///
  /// In en, this message translates to:
  /// **'nothing streaming for'**
  String get nothingStreaming;

  /// No description provided for @open3.
  ///
  /// In en, this message translates to:
  /// **'open on'**
  String get open3;

  /// No description provided for @paused.
  ///
  /// In en, this message translates to:
  /// **'paused'**
  String get paused;

  /// No description provided for @picked2.
  ///
  /// In en, this message translates to:
  /// **'picked'**
  String get picked2;

  /// No description provided for @runoffRound.
  ///
  /// In en, this message translates to:
  /// **'runoff · round'**
  String get runoffRound;

  /// No description provided for @watch2.
  ///
  /// In en, this message translates to:
  /// **'watch on'**
  String get watch2;

  /// No description provided for @watching2.
  ///
  /// In en, this message translates to:
  /// **'watching with'**
  String get watching2;

  /// No description provided for @reviewBelowThenBringWhatLooks.
  ///
  /// In en, this message translates to:
  /// **'— review below, then bring in what looks right'**
  String get reviewBelowThenBringWhatLooks;

  /// No description provided for @tryDifferentRegion.
  ///
  /// In en, this message translates to:
  /// **'— try a different region'**
  String get tryDifferentRegion;

  /// No description provided for @betweenFirstLastFrame.
  ///
  /// In en, this message translates to:
  /// **'between the first and last frame'**
  String get betweenFirstLastFrame;

  /// No description provided for @moreItems.
  ///
  /// In en, this message translates to:
  /// **'more items'**
  String get moreItems;

  /// No description provided for @mostly.
  ///
  /// In en, this message translates to:
  /// **'mostly'**
  String get mostly;

  /// No description provided for @ofMoviesFromEra.
  ///
  /// In en, this message translates to:
  /// **'of movies from this era'**
  String get ofMoviesFromEra;

  /// No description provided for @onWeekends.
  ///
  /// In en, this message translates to:
  /// **'on weekends'**
  String get onWeekends;

  /// No description provided for @receipt.
  ///
  /// In en, this message translates to:
  /// **'receipt'**
  String get receipt;

  /// No description provided for @withSomeone.
  ///
  /// In en, this message translates to:
  /// **'with someone'**
  String get withSomeone;

  /// No description provided for @yourTop.
  ///
  /// In en, this message translates to:
  /// **'your top'**
  String get yourTop;

  /// No description provided for @aShuttleCapsuleLaunchedEachEvening.
  ///
  /// In en, this message translates to:
  /// **'a shuttle, a capsule launched for each evening'**
  String get aShuttleCapsuleLaunchedEachEvening;

  /// No description provided for @aShuttleClearedLaunch.
  ///
  /// In en, this message translates to:
  /// **'a shuttle, cleared for launch'**
  String get aShuttleClearedLaunch;

  /// No description provided for @anEmptySkyWaiting.
  ///
  /// In en, this message translates to:
  /// **'an empty sky, waiting'**
  String get anEmptySkyWaiting;

  /// No description provided for @berth.
  ///
  /// In en, this message translates to:
  /// **'berth'**
  String get berth;

  /// No description provided for @berthsNearViewportGoodOnes.
  ///
  /// In en, this message translates to:
  /// **'berths near the viewport are the good ones'**
  String get berthsNearViewportGoodOnes;

  /// No description provided for @boardAnotherEvening.
  ///
  /// In en, this message translates to:
  /// **'board another evening'**
  String get boardAnotherEvening;

  /// No description provided for @boardFlight.
  ///
  /// In en, this message translates to:
  /// **'board the flight'**
  String get boardFlight;

  /// No description provided for @cancelFlight.
  ///
  /// In en, this message translates to:
  /// **'cancel the flight?'**
  String get cancelFlight;

  /// No description provided for @cancelLaunch.
  ///
  /// In en, this message translates to:
  /// **'cancel the launch?'**
  String get cancelLaunch;

  /// No description provided for @cancelTrip.
  ///
  /// In en, this message translates to:
  /// **'cancel the trip?'**
  String get cancelTrip;

  /// No description provided for @charted.
  ///
  /// In en, this message translates to:
  /// **'charted'**
  String get charted;

  /// No description provided for @chooseBerthTonight.
  ///
  /// In en, this message translates to:
  /// **'choose a berth for tonight'**
  String get chooseBerthTonight;

  /// No description provided for @chooseBerth.
  ///
  /// In en, this message translates to:
  /// **'choose your berth'**
  String get chooseBerth;

  /// No description provided for @clearedOrbit.
  ///
  /// In en, this message translates to:
  /// **'cleared for orbit'**
  String get clearedOrbit;

  /// No description provided for @confirmBerth.
  ///
  /// In en, this message translates to:
  /// **'confirm berth'**
  String get confirmBerth;

  /// No description provided for @confirmLaunch.
  ///
  /// In en, this message translates to:
  /// **'confirm launch'**
  String get confirmLaunch;

  /// No description provided for @gate.
  ///
  /// In en, this message translates to:
  /// **'GATE'**
  String get gate;

  /// No description provided for @inOrbit.
  ///
  /// In en, this message translates to:
  /// **'in orbit'**
  String get inOrbit;

  /// No description provided for @launch.
  ///
  /// In en, this message translates to:
  /// **'launch'**
  String get launch;

  /// No description provided for @launchAnotherEvening.
  ///
  /// In en, this message translates to:
  /// **'launch another evening'**
  String get launchAnotherEvening;

  /// No description provided for @logEveningLightFirstStar.
  ///
  /// In en, this message translates to:
  /// **'log an evening to light the first star'**
  String get logEveningLightFirstStar;

  /// No description provided for @logAnotherEvening.
  ///
  /// In en, this message translates to:
  /// **'log another evening'**
  String get logAnotherEvening;

  /// No description provided for @logOneLightFirstStar.
  ///
  /// In en, this message translates to:
  /// **'log one to light the first star'**
  String get logOneLightFirstStar;

  /// No description provided for @nothingLaunchedYet.
  ///
  /// In en, this message translates to:
  /// **'nothing launched yet'**
  String get nothingLaunchedYet;

  /// No description provided for @pickBerth.
  ///
  /// In en, this message translates to:
  /// **'pick a berth'**
  String get pickBerth;

  /// No description provided for @pickDate.
  ///
  /// In en, this message translates to:
  /// **'pick date'**
  String get pickDate;

  /// No description provided for @pickWhatSStillEnginesCool.
  ///
  /// In en, this message translates to:
  /// **'pick what\'s still with you as the engines cool'**
  String get pickWhatSStillEnginesCool;

  /// No description provided for @plantAnotherEvening.
  ///
  /// In en, this message translates to:
  /// **'plant another evening'**
  String get plantAnotherEvening;

  /// No description provided for @pleaseStowThingsLaunchComingUp.
  ///
  /// In en, this message translates to:
  /// **'please stow your things — launch is coming up'**
  String get pleaseStowThingsLaunchComingUp;

  /// No description provided for @pullReleaseJustTap.
  ///
  /// In en, this message translates to:
  /// **'pull the release — or just tap'**
  String get pullReleaseJustTap;

  /// No description provided for @readyLaunch.
  ///
  /// In en, this message translates to:
  /// **'ready for launch?'**
  String get readyLaunch;

  /// No description provided for @rightByViewport.
  ///
  /// In en, this message translates to:
  /// **'right by the viewport'**
  String get rightByViewport;

  /// No description provided for @sealingHatch.
  ///
  /// In en, this message translates to:
  /// **'sealing the hatch…'**
  String get sealingHatch;

  /// No description provided for @clearingTower.
  ///
  /// In en, this message translates to:
  /// **'clearing the tower'**
  String get clearingTower;

  /// No description provided for @settledBerth.
  ///
  /// In en, this message translates to:
  /// **'settled in — berth'**
  String get settledBerth;

  /// No description provided for @theFlightLog.
  ///
  /// In en, this message translates to:
  /// **'the flight log'**
  String get theFlightLog;

  /// No description provided for @thePadLightsStillUp.
  ///
  /// In en, this message translates to:
  /// **'the pad lights are still up'**
  String get thePadLightsStillUp;

  /// No description provided for @theShuttle.
  ///
  /// In en, this message translates to:
  /// **'the shuttle'**
  String get theShuttle;

  /// No description provided for @tonightSLaunch.
  ///
  /// In en, this message translates to:
  /// **'tonight\'s launch'**
  String get tonightSLaunch;

  /// No description provided for @traceSkySeeEveryOne.
  ///
  /// In en, this message translates to:
  /// **'trace the sky to see every one'**
  String get traceSkySeeEveryOne;

  /// No description provided for @turnBackGate.
  ///
  /// In en, this message translates to:
  /// **'turn back at the gate?'**
  String get turnBackGate;

  /// No description provided for @launchedIntoOrbit.
  ///
  /// In en, this message translates to:
  /// **'· launched into orbit'**
  String get launchedIntoOrbit;

  /// No description provided for @yourDiaryBecomesNightSkyFilling.
  ///
  /// In en, this message translates to:
  /// **'your diary becomes a night sky, filling in with stars'**
  String get yourDiaryBecomesNightSkyFilling;

  /// No description provided for @launchTonightIntoOrbit.
  ///
  /// In en, this message translates to:
  /// **'launch tonight into orbit'**
  String get launchTonightIntoOrbit;

  /// No description provided for @plantTonightBed.
  ///
  /// In en, this message translates to:
  /// **'plant tonight in the bed'**
  String get plantTonightBed;

  /// No description provided for @tearOffTonightSPass.
  ///
  /// In en, this message translates to:
  /// **'tear off tonight\'s pass'**
  String get tearOffTonightSPass;

  /// No description provided for @tuckTonightSTicketAway.
  ///
  /// In en, this message translates to:
  /// **'tuck tonight\'s ticket away'**
  String get tuckTonightSTicketAway;

  /// No description provided for @youReBothUnlimitedNowEnjoy.
  ///
  /// In en, this message translates to:
  /// **'you\'re both unlimited now — enjoy watching together'**
  String get youReBothUnlimitedNowEnjoy;

  /// No description provided for @youReUnlimitedNowEnjoyEvenings.
  ///
  /// In en, this message translates to:
  /// **'you\'re unlimited now — enjoy the evenings'**
  String get youReUnlimitedNowEnjoyEvenings;

  /// No description provided for @great.
  ///
  /// In en, this message translates to:
  /// **'great'**
  String get great;

  /// No description provided for @alreadyYours.
  ///
  /// In en, this message translates to:
  /// **'already yours'**
  String get alreadyYours;

  /// No description provided for @who.
  ///
  /// In en, this message translates to:
  /// **'who is this for?'**
  String get who;

  /// No description provided for @forHowLong.
  ///
  /// In en, this message translates to:
  /// **'for how long?'**
  String get forHowLong;

  /// No description provided for @whatSIncluded.
  ///
  /// In en, this message translates to:
  /// **'what\'s included'**
  String get whatSIncluded;

  /// No description provided for @giftSubscriptionSomeoneClose.
  ///
  /// In en, this message translates to:
  /// **'gift a subscription to someone close'**
  String get giftSubscriptionSomeoneClose;

  /// No description provided for @goPremium2.
  ///
  /// In en, this message translates to:
  /// **'go premium for'**
  String get goPremium2;

  /// No description provided for @then.
  ///
  /// In en, this message translates to:
  /// **'then'**
  String get then;

  /// No description provided for @perMonthCancelAnytime.
  ///
  /// In en, this message translates to:
  /// **'per month · cancel anytime'**
  String get perMonthCancelAnytime;

  /// No description provided for @mo.
  ///
  /// In en, this message translates to:
  /// **'mo'**
  String get mo;

  /// No description provided for @onePaymentWholePeriod.
  ///
  /// In en, this message translates to:
  /// **'one payment for the whole period'**
  String get onePaymentWholePeriod;

  /// No description provided for @tanPremium.
  ///
  /// In en, this message translates to:
  /// **'tanè premium'**
  String get tanPremium;

  /// No description provided for @oneCozyEveningTwoNoLimits.
  ///
  /// In en, this message translates to:
  /// **'one cozy evening for two — no limits for either of you'**
  String get oneCozyEveningTwoNoLimits;

  /// No description provided for @aLittleMoreRoomEvenings.
  ///
  /// In en, this message translates to:
  /// **'a little more room for your evenings'**
  String get aLittleMoreRoomEvenings;

  /// No description provided for @justMe.
  ///
  /// In en, this message translates to:
  /// **'just me'**
  String get justMe;

  /// No description provided for @forAlone.
  ///
  /// In en, this message translates to:
  /// **'for you alone'**
  String get forAlone;

  /// No description provided for @aCouple.
  ///
  /// In en, this message translates to:
  /// **'a couple'**
  String get aCouple;

  /// No description provided for @aBetterDealTwo.
  ///
  /// In en, this message translates to:
  /// **'a better deal for two'**
  String get aBetterDealTwo;

  /// No description provided for @betterValue.
  ///
  /// In en, this message translates to:
  /// **'better value'**
  String get betterValue;

  /// No description provided for @month.
  ///
  /// In en, this message translates to:
  /// **'month'**
  String get month;

  /// No description provided for @sixMonths.
  ///
  /// In en, this message translates to:
  /// **'six months'**
  String get sixMonths;

  /// No description provided for @year.
  ///
  /// In en, this message translates to:
  /// **'year'**
  String get year;

  /// No description provided for @perPerson.
  ///
  /// In en, this message translates to:
  /// **'per person'**
  String get perPerson;

  /// No description provided for @unlimitedTanAsks.
  ///
  /// In en, this message translates to:
  /// **'unlimited tanè asks'**
  String get unlimitedTanAsks;

  /// No description provided for @freeTier3Month.
  ///
  /// In en, this message translates to:
  /// **'free tier — 3 a month'**
  String get freeTier3Month;

  /// No description provided for @asManyFavoriteFilmsLike.
  ///
  /// In en, this message translates to:
  /// **'as many favorite films as you like'**
  String get asManyFavoriteFilmsLike;

  /// No description provided for @freeTierUp5.
  ///
  /// In en, this message translates to:
  /// **'free tier — up to 5'**
  String get freeTierUp5;

  /// No description provided for @spaceShuttleLogTheme.
  ///
  /// In en, this message translates to:
  /// **'\"space shuttle\" log theme'**
  String get spaceShuttleLogTheme;

  /// No description provided for @exclusivePremium.
  ///
  /// In en, this message translates to:
  /// **'exclusive to premium'**
  String get exclusivePremium;

  /// No description provided for @theGiftReady.
  ///
  /// In en, this message translates to:
  /// **'the gift is ready'**
  String get theGiftReady;

  /// No description provided for @theGift.
  ///
  /// In en, this message translates to:
  /// **'the gift for'**
  String get theGift;

  /// No description provided for @isReady.
  ///
  /// In en, this message translates to:
  /// **'is ready'**
  String get isReady;

  /// No description provided for @sendCodeLlNeedEnteredSettings.
  ///
  /// In en, this message translates to:
  /// **'send this code — it\'ll need to be entered in settings to turn premium on'**
  String get sendCodeLlNeedEnteredSettings;

  /// No description provided for @for2.
  ///
  /// In en, this message translates to:
  /// **'for'**
  String get for2;

  /// No description provided for @giftingTanPremiumSubscription.
  ///
  /// In en, this message translates to:
  /// **'gifting you a tanè premium subscription 🎁'**
  String get giftingTanPremiumSubscription;

  /// No description provided for @code.
  ///
  /// In en, this message translates to:
  /// **'code'**
  String get code;

  /// No description provided for @shareGift.
  ///
  /// In en, this message translates to:
  /// **'share the gift'**
  String get shareGift;

  /// No description provided for @whoGift.
  ///
  /// In en, this message translates to:
  /// **'who is this gift for?'**
  String get whoGift;

  /// No description provided for @nameOptional.
  ///
  /// In en, this message translates to:
  /// **'name (optional)'**
  String get nameOptional;

  /// No description provided for @warmWordsGiftOptional.
  ///
  /// In en, this message translates to:
  /// **'warm words for the gift (optional)'**
  String get warmWordsGiftOptional;

  /// No description provided for @howLongShouldGiftLast.
  ///
  /// In en, this message translates to:
  /// **'how long should the gift last?'**
  String get howLongShouldGiftLast;

  /// No description provided for @aGiftCostsLessThanRegular.
  ///
  /// In en, this message translates to:
  /// **'a gift costs less than the regular subscription — it\'s a gift, not a purchase for yourself'**
  String get aGiftCostsLessThanRegular;

  /// No description provided for @gift.
  ///
  /// In en, this message translates to:
  /// **'gift for'**
  String get gift;

  /// No description provided for @cheaperThanRegularSubscriptionSamePeriod.
  ///
  /// In en, this message translates to:
  /// **'cheaper than the regular subscription for the same period, by'**
  String get cheaperThanRegularSubscriptionSamePeriod;

  /// No description provided for @aOneTimePaymentNoAuto.
  ///
  /// In en, this message translates to:
  /// **'a one-time payment, no auto-renewal'**
  String get aOneTimePaymentNoAuto;

  /// No description provided for @giftPremium.
  ///
  /// In en, this message translates to:
  /// **'gift premium'**
  String get giftPremium;

  /// No description provided for @giftCozyLimitFreeEveningsPartner.
  ///
  /// In en, this message translates to:
  /// **'gift cozy, limit-free evenings — to a partner, a friend, or someone you love'**
  String get giftCozyLimitFreeEveningsPartner;

  /// No description provided for @openPremium.
  ///
  /// In en, this message translates to:
  /// **'open premium'**
  String get openPremium;

  /// No description provided for @outTanAsksMonth.
  ///
  /// In en, this message translates to:
  /// **'out of tanè asks for this month'**
  String get outTanAsksMonth;

  /// No description provided for @theFreeTierIncludes3Questions.
  ///
  /// In en, this message translates to:
  /// **'the free tier includes 3 questions a month — premium removes the limit'**
  String get theFreeTierIncludes3Questions;

  /// No description provided for @favoritesLimitReached.
  ///
  /// In en, this message translates to:
  /// **'favorites limit reached'**
  String get favoritesLimitReached;

  /// No description provided for @theFreeTierHoldsUp5.
  ///
  /// In en, this message translates to:
  /// **'the free tier holds up to 5 favorite films — premium removes the limit'**
  String get theFreeTierHoldsUp5;

  /// No description provided for @listsLimitReached.
  ///
  /// In en, this message translates to:
  /// **'lists limit reached'**
  String get listsLimitReached;

  /// No description provided for @theFreeTierHoldsUp52.
  ///
  /// In en, this message translates to:
  /// **'the free tier holds up to 5 lists — premium removes the limit'**
  String get theFreeTierHoldsUp52;

  /// No description provided for @asManyListsLike.
  ///
  /// In en, this message translates to:
  /// **'as many lists as you like'**
  String get asManyListsLike;

  /// No description provided for @freeTierUp5Lists.
  ///
  /// In en, this message translates to:
  /// **'free tier — up to 5 lists'**
  String get freeTierUp5Lists;

  /// No description provided for @keepsakeExportPdf.
  ///
  /// In en, this message translates to:
  /// **'keepsake export (pdf)'**
  String get keepsakeExportPdf;

  /// No description provided for @yourDiaryWrappedPdfSavePrint.
  ///
  /// In en, this message translates to:
  /// **'your diary or your wrapped, as a pdf to save or print'**
  String get yourDiaryWrappedPdfSavePrint;

  /// No description provided for @couldnTPutKeepsakeTogetherTry.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t put the keepsake together — try again'**
  String get couldnTPutKeepsakeTogetherTry;

  /// No description provided for @whatGoes.
  ///
  /// In en, this message translates to:
  /// **'what goes in it'**
  String get whatGoes;

  /// No description provided for @everyLoggedEvening.
  ///
  /// In en, this message translates to:
  /// **'every logged evening'**
  String get everyLoggedEvening;

  /// No description provided for @groupedMonthByMonthOldestFirst.
  ///
  /// In en, this message translates to:
  /// **'grouped month by month, oldest first'**
  String get groupedMonthByMonthOldestFirst;

  /// No description provided for @theSameSoftPaperLook.
  ///
  /// In en, this message translates to:
  /// **'the same soft, paper look'**
  String get theSameSoftPaperLook;

  /// No description provided for @noWatermarkNoUpgradeNagPage.
  ///
  /// In en, this message translates to:
  /// **'no watermark, no upgrade nag on the page'**
  String get noWatermarkNoUpgradeNagPage;

  /// No description provided for @yoursKeep.
  ///
  /// In en, this message translates to:
  /// **'yours to keep'**
  String get yoursKeep;

  /// No description provided for @savePrintSendChoice.
  ///
  /// In en, this message translates to:
  /// **'save it, print it, or send it — your choice'**
  String get savePrintSendChoice;

  /// No description provided for @includedPremium.
  ///
  /// In en, this message translates to:
  /// **'included with premium'**
  String get includedPremium;

  /// No description provided for @makeMyKeepsake.
  ///
  /// In en, this message translates to:
  /// **'make my keepsake'**
  String get makeMyKeepsake;

  /// No description provided for @unlockPremium.
  ///
  /// In en, this message translates to:
  /// **'unlock with premium'**
  String get unlockPremium;

  /// No description provided for @aKeepsakePrintSaveSend.
  ///
  /// In en, this message translates to:
  /// **'a keepsake to print, save, or send'**
  String get aKeepsakePrintSaveSend;

  /// No description provided for @yourDiary.
  ///
  /// In en, this message translates to:
  /// **'your diary'**
  String get yourDiary;

  /// No description provided for @wrapped.
  ///
  /// In en, this message translates to:
  /// **'wrapped'**
  String get wrapped;

  /// No description provided for @choosePeriod.
  ///
  /// In en, this message translates to:
  /// **'choose a period'**
  String get choosePeriod;

  /// No description provided for @groupedMonthByMonthOldestFirst2.
  ///
  /// In en, this message translates to:
  /// **'grouped month by month, oldest first, with real posters'**
  String get groupedMonthByMonthOldestFirst2;

  /// No description provided for @anyPeriodVeLogged.
  ///
  /// In en, this message translates to:
  /// **'any period you\'ve logged in'**
  String get anyPeriodVeLogged;

  /// No description provided for @thisMonthYearAllTimeAny.
  ///
  /// In en, this message translates to:
  /// **'this month, this year, all time, or any earlier one'**
  String get thisMonthYearAllTimeAny;

  /// No description provided for @theFullWrappedStory.
  ///
  /// In en, this message translates to:
  /// **'the full wrapped story'**
  String get theFullWrappedStory;

  /// No description provided for @totalsGenresRhythmArchetypeTopReviews.
  ///
  /// In en, this message translates to:
  /// **'totals, genres, rhythm, your archetype, top reviews'**
  String get totalsGenresRhythmArchetypeTopReviews;

  /// No description provided for @aKeepsakeReceiptEnd.
  ///
  /// In en, this message translates to:
  /// **'a keepsake receipt at the end'**
  String get aKeepsakeReceiptEnd;

  /// No description provided for @makeMyWrapped.
  ///
  /// In en, this message translates to:
  /// **'make my wrapped'**
  String get makeMyWrapped;

  /// No description provided for @couldnTPutWrappedTogetherTry.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t put your wrapped together — try again'**
  String get couldnTPutWrappedTogetherTry;

  /// No description provided for @turnDiaryIntoKeepsake.
  ///
  /// In en, this message translates to:
  /// **'turn your diary into a keepsake'**
  String get turnDiaryIntoKeepsake;

  /// No description provided for @premiumCanExportWholeDiaryWrapped.
  ///
  /// In en, this message translates to:
  /// **'premium can export your whole diary — or a wrapped recap of any period — as a soft, paper-styled pdf to save, print, or send'**
  String get premiumCanExportWholeDiaryWrapped;

  /// No description provided for @andDeveloperWouldReallyGlad.
  ///
  /// In en, this message translates to:
  /// **'and the developer would be really glad'**
  String get andDeveloperWouldReallyGlad;

  /// No description provided for @saveWrapped.
  ///
  /// In en, this message translates to:
  /// **'save this wrapped'**
  String get saveWrapped;

  /// No description provided for @premiumCanTurnIntoSoftPaper.
  ///
  /// In en, this message translates to:
  /// **'premium can turn this into a soft, paper-styled pdf — with the receipt at the end — to save, print, or send'**
  String get premiumCanTurnIntoSoftPaper;

  /// No description provided for @aWrappedOwn.
  ///
  /// In en, this message translates to:
  /// **'a wrapped of your own'**
  String get aWrappedOwn;

  /// No description provided for @aTripSeasonRelationshipAnyStretch.
  ///
  /// In en, this message translates to:
  /// **'a trip, a season, a relationship — any stretch you name'**
  String get aTripSeasonRelationshipAnyStretch;

  /// No description provided for @giveNameFirst.
  ///
  /// In en, this message translates to:
  /// **'give it a name first'**
  String get giveNameFirst;

  /// No description provided for @pickDateRangeToo.
  ///
  /// In en, this message translates to:
  /// **'pick a date range too'**
  String get pickDateRangeToo;

  /// No description provided for @chooseStartEnd.
  ///
  /// In en, this message translates to:
  /// **'choose start and end'**
  String get chooseStartEnd;

  /// No description provided for @whatShouldWeCall.
  ///
  /// In en, this message translates to:
  /// **'what should we call it?'**
  String get whatShouldWeCall;

  /// No description provided for @vacationTurkey.
  ///
  /// In en, this message translates to:
  /// **'vacation in turkey'**
  String get vacationTurkey;

  /// No description provided for @whichDates.
  ///
  /// In en, this message translates to:
  /// **'which dates?'**
  String get whichDates;

  /// No description provided for @aBiggerCirclePremium.
  ///
  /// In en, this message translates to:
  /// **'a bigger circle is premium'**
  String get aBiggerCirclePremium;

  /// No description provided for @aCoupleStaysFreeForeverPremium.
  ///
  /// In en, this message translates to:
  /// **'a couple stays free forever — premium lets you watch together as a company, three and up'**
  String get aCoupleStaysFreeForeverPremium;

  /// No description provided for @premiumBiggerCircle.
  ///
  /// In en, this message translates to:
  /// **'premium for a bigger circle'**
  String get premiumBiggerCircle;

  /// No description provided for @watchTogetherCompany.
  ///
  /// In en, this message translates to:
  /// **'watch together as a company'**
  String get watchTogetherCompany;

  /// No description provided for @aCoupleAlwaysFreeThreeUp.
  ///
  /// In en, this message translates to:
  /// **'a couple is always free — three and up is premium'**
  String get aCoupleAlwaysFreeThreeUp;

  /// No description provided for @youVsCirclePremium.
  ///
  /// In en, this message translates to:
  /// **'you vs your circle is premium'**
  String get youVsCirclePremium;

  /// No description provided for @seeWhoSuggestsMoreWhatWatch.
  ///
  /// In en, this message translates to:
  /// **'see who suggests more of what you watch together — premium unlocks the numbers'**
  String get seeWhoSuggestsMoreWhatWatch;

  /// No description provided for @openPremium2.
  ///
  /// In en, this message translates to:
  /// **'open with premium'**
  String get openPremium2;

  /// No description provided for @youVsCircle.
  ///
  /// In en, this message translates to:
  /// **'you vs your circle'**
  String get youVsCircle;

  /// No description provided for @inWrappedStatsWhoSuggestsMore.
  ///
  /// In en, this message translates to:
  /// **'in wrapped and stats — who suggests more of what you watch'**
  String get inWrappedStatsWhoSuggestsMore;

  /// No description provided for @yourTrend.
  ///
  /// In en, this message translates to:
  /// **'your trend'**
  String get yourTrend;

  /// No description provided for @aMonthByMonthChartOwn.
  ///
  /// In en, this message translates to:
  /// **'a month-by-month chart of your own activity, not just a snapshot'**
  String get aMonthByMonthChartOwn;

  /// No description provided for @yourPeriods.
  ///
  /// In en, this message translates to:
  /// **'your periods'**
  String get yourPeriods;

  /// No description provided for @nameNewPeriod.
  ///
  /// In en, this message translates to:
  /// **'name a new period'**
  String get nameNewPeriod;

  /// No description provided for @deletePeriod.
  ///
  /// In en, this message translates to:
  /// **'delete this period?'**
  String get deletePeriod;

  /// No description provided for @yourTrendPremium.
  ///
  /// In en, this message translates to:
  /// **'your trend is premium'**
  String get yourTrendPremium;

  /// No description provided for @seeMonthByMonthHowMuch.
  ///
  /// In en, this message translates to:
  /// **'see month by month how much you\'re watching, not just one period at a time — premium unlocks the chart'**
  String get seeMonthByMonthHowMuch;

  /// No description provided for @aQuietRecordBeingHonestYourself.
  ///
  /// In en, this message translates to:
  /// **'a quiet record of being honest with yourself'**
  String get aQuietRecordBeingHonestYourself;

  /// No description provided for @sincerity.
  ///
  /// In en, this message translates to:
  /// **'sincerity'**
  String get sincerity;

  /// No description provided for @couldnTLoadTryAgain.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load this — try again'**
  String get couldnTLoadTryAgain;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'history'**
  String get history;

  /// No description provided for @notRatingLevelJustNumberGrows.
  ///
  /// In en, this message translates to:
  /// **'not a rating or a level — just a number that grows when you\'re honest with yourself'**
  String get notRatingLevelJustNumberGrows;

  /// No description provided for @earnedWhen.
  ///
  /// In en, this message translates to:
  /// **'earned when you:'**
  String get earnedWhen;

  /// No description provided for @finallyCloseSomethingSBeenSitting.
  ///
  /// In en, this message translates to:
  /// **'finally close something that\'s been sitting in your plans — watch it, or honestly decide it\'s not for you'**
  String get finallyCloseSomethingSBeenSitting;

  /// No description provided for @changeOldRatingInsteadDefending.
  ///
  /// In en, this message translates to:
  /// **'change an old rating instead of defending it'**
  String get changeOldRatingInsteadDefending;

  /// No description provided for @dropSomethingHonestlyWriteWhy.
  ///
  /// In en, this message translates to:
  /// **'drop something and honestly write why'**
  String get dropSomethingHonestlyWriteWhy;

  /// No description provided for @stakePointsRecommendationFriendLands.
  ///
  /// In en, this message translates to:
  /// **'stake points on a recommendation to a friend — and it lands'**
  String get stakePointsRecommendationFriendLands;

  /// No description provided for @spentWhen.
  ///
  /// In en, this message translates to:
  /// **'spent when you:'**
  String get spentWhen;

  /// No description provided for @stakePointsRecommendationFriendRiskWon.
  ///
  /// In en, this message translates to:
  /// **'stake points on a recommendation to a friend — the risk it won\'t land'**
  String get stakePointsRecommendationFriendRiskWon;

  /// No description provided for @unlockSpoilerEarly.
  ///
  /// In en, this message translates to:
  /// **'unlock a spoiler early'**
  String get unlockSpoilerEarly;

  /// No description provided for @payOffDebtFromSomethingS.
  ///
  /// In en, this message translates to:
  /// **'pay off the debt from something that\'s sat untouched in your plans too long'**
  String get payOffDebtFromSomethingS;

  /// No description provided for @thereNoPointsHowManyEntries.
  ///
  /// In en, this message translates to:
  /// **'there are no points for how many entries, ratings, or notes you write — only for honest calls. and this number never locks or unlocks any feature — it just exists.'**
  String get thereNoPointsHowManyEntries;

  /// No description provided for @showFriends.
  ///
  /// In en, this message translates to:
  /// **'show to friends'**
  String get showFriends;

  /// No description provided for @privateByDefault.
  ///
  /// In en, this message translates to:
  /// **'private to you by default'**
  String get privateByDefault;

  /// No description provided for @historyWillShowUpHereOnce.
  ///
  /// In en, this message translates to:
  /// **'history will show up here once something honest gets closed'**
  String get historyWillShowUpHereOnce;

  /// No description provided for @closedLongWait.
  ///
  /// In en, this message translates to:
  /// **'closed a long wait'**
  String get closedLongWait;

  /// No description provided for @revisedOldRating.
  ///
  /// In en, this message translates to:
  /// **'revised an old rating'**
  String get revisedOldRating;

  /// No description provided for @aRecommendationLanded.
  ///
  /// In en, this message translates to:
  /// **'a recommendation landed'**
  String get aRecommendationLanded;

  /// No description provided for @droppedHonestlyReason.
  ///
  /// In en, this message translates to:
  /// **'dropped it honestly, with a reason'**
  String get droppedHonestlyReason;

  /// No description provided for @stakedRecommendation.
  ///
  /// In en, this message translates to:
  /// **'staked on a recommendation'**
  String get stakedRecommendation;

  /// No description provided for @theStakeDidnTLand.
  ///
  /// In en, this message translates to:
  /// **'the stake didn\'t land'**
  String get theStakeDidnTLand;

  /// No description provided for @earlySpoiler.
  ///
  /// In en, this message translates to:
  /// **'early spoiler'**
  String get earlySpoiler;

  /// No description provided for @debtSettled.
  ///
  /// In en, this message translates to:
  /// **'debt settled'**
  String get debtSettled;

  /// No description provided for @debtSomethingLeftPlans.
  ///
  /// In en, this message translates to:
  /// **'debt for something left in plans'**
  String get debtSomethingLeftPlans;

  /// No description provided for @notMe.
  ///
  /// In en, this message translates to:
  /// **'not for me'**
  String get notMe;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'retry'**
  String get retry;

  /// No description provided for @reviewsProvidedByTmdbTrakt.
  ///
  /// In en, this message translates to:
  /// **'Reviews provided by TMDB and Trakt'**
  String get reviewsProvidedByTmdbTrakt;

  /// No description provided for @watchingSeries2.
  ///
  /// In en, this message translates to:
  /// **'watching a series 🍿'**
  String get watchingSeries2;

  /// No description provided for @lookingCoViewing.
  ///
  /// In en, this message translates to:
  /// **'looking for co-viewing'**
  String get lookingCoViewing;

  /// No description provided for @doNotDisturb.
  ///
  /// In en, this message translates to:
  /// **'do not disturb'**
  String get doNotDisturb;

  /// No description provided for @onPause.
  ///
  /// In en, this message translates to:
  /// **'on pause'**
  String get onPause;

  /// No description provided for @openRecommendations.
  ///
  /// In en, this message translates to:
  /// **'open to recommendations'**
  String get openRecommendations;

  /// No description provided for @pickFavoriteFilms.
  ///
  /// In en, this message translates to:
  /// **'pick your favorite films'**
  String get pickFavoriteFilms;

  /// No description provided for @detailedStats.
  ///
  /// In en, this message translates to:
  /// **'detailed stats'**
  String get detailedStats;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'name'**
  String get name;

  /// No description provided for @status2.
  ///
  /// In en, this message translates to:
  /// **'status'**
  String get status2;

  /// No description provided for @yourOwnClearFieldStatusDisappears.
  ///
  /// In en, this message translates to:
  /// **'your own, or clear the field — the status disappears'**
  String get yourOwnClearFieldStatusDisappears;

  /// No description provided for @stats.
  ///
  /// In en, this message translates to:
  /// **'stats'**
  String get stats;

  /// No description provided for @couldnTLoadStats.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load stats'**
  String get couldnTLoadStats;

  /// No description provided for @directors.
  ///
  /// In en, this message translates to:
  /// **'directors'**
  String get directors;

  /// No description provided for @rewatchedMost.
  ///
  /// In en, this message translates to:
  /// **'rewatched most'**
  String get rewatchedMost;

  /// No description provided for @noRepeatsYet.
  ///
  /// In en, this message translates to:
  /// **'no repeats yet'**
  String get noRepeatsYet;

  /// No description provided for @allTime.
  ///
  /// In en, this message translates to:
  /// **'all time'**
  String get allTime;

  /// No description provided for @h.
  ///
  /// In en, this message translates to:
  /// **'h'**
  String get h;

  /// No description provided for @inDiary.
  ///
  /// In en, this message translates to:
  /// **'in the diary'**
  String get inDiary;

  /// No description provided for @screenings.
  ///
  /// In en, this message translates to:
  /// **'screenings'**
  String get screenings;

  /// No description provided for @mon.
  ///
  /// In en, this message translates to:
  /// **'mon'**
  String get mon;

  /// No description provided for @tue.
  ///
  /// In en, this message translates to:
  /// **'tue'**
  String get tue;

  /// No description provided for @wed.
  ///
  /// In en, this message translates to:
  /// **'wed'**
  String get wed;

  /// No description provided for @thu.
  ///
  /// In en, this message translates to:
  /// **'thu'**
  String get thu;

  /// No description provided for @fri.
  ///
  /// In en, this message translates to:
  /// **'fri'**
  String get fri;

  /// No description provided for @sat.
  ///
  /// In en, this message translates to:
  /// **'sat'**
  String get sat;

  /// No description provided for @sun.
  ///
  /// In en, this message translates to:
  /// **'sun'**
  String get sun;

  /// No description provided for @weeklyRhythm.
  ///
  /// In en, this message translates to:
  /// **'weekly rhythm'**
  String get weeklyRhythm;

  /// No description provided for @yourHour.
  ///
  /// In en, this message translates to:
  /// **'your hour'**
  String get yourHour;

  /// No description provided for @amongOtherViewers.
  ///
  /// In en, this message translates to:
  /// **'among other viewers'**
  String get amongOtherViewers;

  /// No description provided for @genres.
  ///
  /// In en, this message translates to:
  /// **'genres'**
  String get genres;

  /// No description provided for @n2020s.
  ///
  /// In en, this message translates to:
  /// **'2020s'**
  String get n2020s;

  /// No description provided for @n2010s.
  ///
  /// In en, this message translates to:
  /// **'2010s'**
  String get n2010s;

  /// No description provided for @before2010s.
  ///
  /// In en, this message translates to:
  /// **'before 2010s'**
  String get before2010s;

  /// No description provided for @whichEraFilmsFrom.
  ///
  /// In en, this message translates to:
  /// **'which era your films are from'**
  String get whichEraFilmsFrom;

  /// No description provided for @howWatched.
  ///
  /// In en, this message translates to:
  /// **'how you watched'**
  String get howWatched;

  /// No description provided for @solo.
  ///
  /// In en, this message translates to:
  /// **'solo'**
  String get solo;

  /// No description provided for @firstWatch2.
  ///
  /// In en, this message translates to:
  /// **'first watch'**
  String get firstWatch2;

  /// No description provided for @noDataYet.
  ///
  /// In en, this message translates to:
  /// **'no data yet'**
  String get noDataYet;

  /// No description provided for @favoriteReviewPeriod.
  ///
  /// In en, this message translates to:
  /// **'favorite review of the period'**
  String get favoriteReviewPeriod;

  /// No description provided for @firstLast.
  ///
  /// In en, this message translates to:
  /// **'first and last'**
  String get firstLast;

  /// No description provided for @days.
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get days;

  /// No description provided for @day.
  ///
  /// In en, this message translates to:
  /// **'day'**
  String get day;

  /// No description provided for @days2.
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get days2;

  /// No description provided for @pickUp5.
  ///
  /// In en, this message translates to:
  /// **'pick up to 5'**
  String get pickUp5;

  /// No description provided for @kinopoiskHdIviOkkoWinkStart.
  ///
  /// In en, this message translates to:
  /// **'Kinopoisk HD · ivi · Okko · Wink · START · KION · Rutube'**
  String get kinopoiskHdIviOkkoWinkStart;

  /// No description provided for @swipeThroughPickAnyPoster.
  ///
  /// In en, this message translates to:
  /// **'swipe through and pick any poster'**
  String get swipeThroughPickAnyPoster;

  /// No description provided for @matchingEra.
  ///
  /// In en, this message translates to:
  /// **'matching era'**
  String get matchingEra;

  /// No description provided for @matchesDescription.
  ///
  /// In en, this message translates to:
  /// **'matches your description'**
  String get matchesDescription;

  /// No description provided for @bestMatch.
  ///
  /// In en, this message translates to:
  /// **'✦ best match'**
  String get bestMatch;

  /// No description provided for @spiritedAway.
  ///
  /// In en, this message translates to:
  /// **'Spirited Away'**
  String get spiritedAway;

  /// No description provided for @aboutFranchise.
  ///
  /// In en, this message translates to:
  /// **'about the franchise'**
  String get aboutFranchise;

  /// No description provided for @aboutFranchiseHowCameTogether.
  ///
  /// In en, this message translates to:
  /// **'about the franchise and how it came together'**
  String get aboutFranchiseHowCameTogether;

  /// No description provided for @howFranchiseCameTogether.
  ///
  /// In en, this message translates to:
  /// **'how the franchise came together'**
  String get howFranchiseCameTogether;

  /// No description provided for @readMoreWikipedia.
  ///
  /// In en, this message translates to:
  /// **'read more on Wikipedia →'**
  String get readMoreWikipedia;

  /// No description provided for @arrived.
  ///
  /// In en, this message translates to:
  /// **'arrived'**
  String get arrived;

  /// No description provided for @balanceYear.
  ///
  /// In en, this message translates to:
  /// **'balance of the year'**
  String get balanceYear;

  /// No description provided for @chooseDifferentPeriod.
  ///
  /// In en, this message translates to:
  /// **'choose a different period'**
  String get chooseDifferentPeriod;

  /// No description provided for @years.
  ///
  /// In en, this message translates to:
  /// **'years'**
  String get years;

  /// No description provided for @genreYear.
  ///
  /// In en, this message translates to:
  /// **'genre of the year'**
  String get genreYear;

  /// No description provided for @allTime2.
  ///
  /// In en, this message translates to:
  /// **'all time'**
  String get allTime2;

  /// No description provided for @sealedTapOpen.
  ///
  /// In en, this message translates to:
  /// **'sealed · tap to open'**
  String get sealedTapOpen;

  /// No description provided for @whatEraMoviesFrom.
  ///
  /// In en, this message translates to:
  /// **'what era your movies are from'**
  String get whatEraMoviesFrom;

  /// No description provided for @whatYearWasMade.
  ///
  /// In en, this message translates to:
  /// **'what your year was made of'**
  String get whatYearWasMade;

  /// No description provided for @totalTime.
  ///
  /// In en, this message translates to:
  /// **'total time'**
  String get totalTime;

  /// No description provided for @whichDayYours.
  ///
  /// In en, this message translates to:
  /// **'which day is yours'**
  String get whichDayYours;

  /// No description provided for @whenWatch.
  ///
  /// In en, this message translates to:
  /// **'when you watch'**
  String get whenWatch;

  /// No description provided for @topRatingPeriod.
  ///
  /// In en, this message translates to:
  /// **'top rating of the period'**
  String get topRatingPeriod;

  /// No description provided for @topPercentile.
  ///
  /// In en, this message translates to:
  /// **'top percentile'**
  String get topPercentile;

  /// No description provided for @months.
  ///
  /// In en, this message translates to:
  /// **'months'**
  String get months;

  /// No description provided for @couldnTLoadSummary.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load this summary'**
  String get couldnTLoadSummary;

  /// No description provided for @newFamiliar.
  ///
  /// In en, this message translates to:
  /// **'new or familiar'**
  String get newFamiliar;

  /// No description provided for @new2.
  ///
  /// In en, this message translates to:
  /// **'new'**
  String get new2;

  /// No description provided for @firstLast2.
  ///
  /// In en, this message translates to:
  /// **'first and last'**
  String get firstLast2;

  /// No description provided for @favoriteRewatch.
  ///
  /// In en, this message translates to:
  /// **'favorite rewatch'**
  String get favoriteRewatch;

  /// No description provided for @rewatches.
  ///
  /// In en, this message translates to:
  /// **'rewatches'**
  String get rewatches;

  /// No description provided for @letter.
  ///
  /// In en, this message translates to:
  /// **'letter'**
  String get letter;

  /// No description provided for @shareLetter.
  ///
  /// In en, this message translates to:
  /// **'share the letter →'**
  String get shareLetter;

  /// No description provided for @shareArchetype.
  ///
  /// In en, this message translates to:
  /// **'share the archetype →'**
  String get shareArchetype;

  /// No description provided for @shareReceipt.
  ///
  /// In en, this message translates to:
  /// **'share the receipt →'**
  String get shareReceipt;

  /// No description provided for @notEnoughDataYet.
  ///
  /// In en, this message translates to:
  /// **'not enough data yet'**
  String get notEnoughDataYet;

  /// No description provided for @notEnoughWatchTimeDataYet.
  ///
  /// In en, this message translates to:
  /// **'not enough watch-time data yet'**
  String get notEnoughWatchTimeDataYet;

  /// No description provided for @notEnoughGenresPictureYet.
  ///
  /// In en, this message translates to:
  /// **'not enough genres for a picture yet'**
  String get notEnoughGenresPictureYet;

  /// No description provided for @directorYear.
  ///
  /// In en, this message translates to:
  /// **'director of the year'**
  String get directorYear;

  /// No description provided for @directorsYear.
  ///
  /// In en, this message translates to:
  /// **'directors of the year'**
  String get directorsYear;

  /// No description provided for @discountsBonuses.
  ///
  /// In en, this message translates to:
  /// **'discounts and bonuses'**
  String get discountsBonuses;

  /// No description provided for @soloCompany.
  ///
  /// In en, this message translates to:
  /// **'solo or company'**
  String get soloCompany;

  /// No description provided for @averageRating.
  ///
  /// In en, this message translates to:
  /// **'average rating'**
  String get averageRating;

  /// No description provided for @startFinish.
  ///
  /// In en, this message translates to:
  /// **'start and finish'**
  String get startFinish;

  /// No description provided for @yourReviews.
  ///
  /// In en, this message translates to:
  /// **'your reviews'**
  String get yourReviews;

  /// No description provided for @yourMovieHour.
  ///
  /// In en, this message translates to:
  /// **'your movie hour'**
  String get yourMovieHour;

  /// No description provided for @yourArchetypeYear.
  ///
  /// In en, this message translates to:
  /// **'your archetype of the year'**
  String get yourArchetypeYear;

  /// No description provided for @yourFilmReel.
  ///
  /// In en, this message translates to:
  /// **'your film reel'**
  String get yourFilmReel;

  /// No description provided for @thisYear.
  ///
  /// In en, this message translates to:
  /// **'this year'**
  String get thisYear;

  /// No description provided for @thisMonth.
  ///
  /// In en, this message translates to:
  /// **'this month'**
  String get thisMonth;

  /// No description provided for @aPeriodOwn.
  ///
  /// In en, this message translates to:
  /// **'a period of your own'**
  String get aPeriodOwn;

  /// No description provided for @whoPicksMore.
  ///
  /// In en, this message translates to:
  /// **'who picks more?'**
  String get whoPicksMore;

  /// No description provided for @yourCircle.
  ///
  /// In en, this message translates to:
  /// **'your circle'**
  String get yourCircle;

  /// No description provided for @youTwo.
  ///
  /// In en, this message translates to:
  /// **'you two'**
  String get youTwo;

  /// No description provided for @aWrappedOwnPremium.
  ///
  /// In en, this message translates to:
  /// **'a wrapped of your own is premium'**
  String get aWrappedOwnPremium;

  /// No description provided for @nameAnyStretchTripSeasonRelationship.
  ///
  /// In en, this message translates to:
  /// **'name any stretch — a trip, a season, a relationship — and get a full wrapped for it'**
  String get nameAnyStretchTripSeasonRelationship;

  /// Plural: day / days — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} day} other {{count} days}}'**
  String nDays(int count);

  /// Plural: stop / stops — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} stop} other {{count} stops}}'**
  String nStops(int count);

  /// Plural: night / nights — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} night} other {{count} nights}}'**
  String nNights(int count);

  /// Plural: launch / launches — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} launch} other {{count} launches}}'**
  String nLaunches(int count);

  /// Plural: item / items — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} item} other {{count} items}}'**
  String nPositions(int count);

  /// Plural: title / titles — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} title} other {{count} titles}}'**
  String nTitles(int count);

  /// Plural: release / releases — count + noun (full-screen release calendar summary).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} release} other {{count} releases}}'**
  String nReleases(int count);

  /// Plural: friend / friends — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} friend} other {{count} friends}}'**
  String nFriends(int count);

  /// Plural: movie / movies — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} movie} other {{count} movies}}'**
  String nMovies(int count);

  /// Plural: review / reviews — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} review} other {{count} reviews}}'**
  String nReviews(int count);

  /// Plural: minute / minutes — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} minute} other {{count} minutes}}'**
  String nMinutes(int count);

  /// Plural: hour / hours — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} hour} other {{count} hours}}'**
  String nHours(int count);

  /// Plural: week / weeks — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} week} other {{count} weeks}}'**
  String nWeeks(int count);

  /// Plural: type / types — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} type} other {{count} types}}'**
  String nTypes(int count);

  /// Plural: genre / genres — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} genre} other {{count} genres}}'**
  String nGenres(int count);

  /// Plural: match / matches — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} match} other {{count} matches}}'**
  String nMatches(int count);

  /// Plural: vote / votes — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} vote} other {{count} votes}}'**
  String nVotes(int count);

  /// Plural: episode / episodes — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} episode} other {{count} episodes}}'**
  String nEpisodes(int count);

  /// Plural: suggestion / suggestions — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} suggestion} other {{count} suggestions}}'**
  String nSuggestions(int count);

  /// Plural: evening / evenings — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} evening} other {{count} evenings}}'**
  String nEvenings(int count);

  /// Plural: item / items — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} item} other {{count} items}}'**
  String nTitlesAsItems(int count);

  /// Plural: sincerity point / sincerity points — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} sincerity point} other {{count} sincerity points}}'**
  String nSincerityPoints(int count);

  /// Plural: word / words — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} word} other {{count} words}}'**
  String nWords(int count);

  /// Plural: screening / screenings — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} screening} other {{count} screenings}}'**
  String nScreenings(int count);

  /// Referral sheet: how many friends have joined with this invite code, plus the XP earned so far.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} friend has joined with your code} other {{count} friends have joined with your code}} — +{xp} so far'**
  String friendsJoinedWithCode(int count, int xp);

  /// Plural: point / points — used for a rating-gap difference ("you disagreed by 3 points").
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} point} other {{count} points}}'**
  String nPoints(int count);

  /// No description provided for @ourDiary.
  ///
  /// In en, this message translates to:
  /// **'our diary'**
  String get ourDiary;

  /// No description provided for @howDiarySPagesLookPlain.
  ///
  /// In en, this message translates to:
  /// **'how the diary\'s pages look — plain paper, or a pastel skin with washi tape and folded corners. change this anytime in settings.'**
  String get howDiarySPagesLookPlain;

  /// No description provided for @cleanPaper.
  ///
  /// In en, this message translates to:
  /// **'clean paper'**
  String get cleanPaper;

  /// No description provided for @tapeFoldedCorners.
  ///
  /// In en, this message translates to:
  /// **'tape & folded corners'**
  String get tapeFoldedCorners;

  /// No description provided for @tuesday.
  ///
  /// In en, this message translates to:
  /// **'tuesday'**
  String get tuesday;

  /// No description provided for @tue914Pm.
  ///
  /// In en, this message translates to:
  /// **'TUE · 9:14 PM'**
  String get tue914Pm;

  /// No description provided for @openingQuoteMark.
  ///
  /// In en, this message translates to:
  /// **'“'**
  String get openingQuoteMark;

  /// No description provided for @russiaFlagEmoji.
  ///
  /// In en, this message translates to:
  /// **'🇷🇺'**
  String get russiaFlagEmoji;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'forgot your password?'**
  String get forgotPassword;

  /// No description provided for @enterEmailAddedDiaryWeLl.
  ///
  /// In en, this message translates to:
  /// **'enter the email you added to your diary and we\'ll send a link to set a new one'**
  String get enterEmailAddedDiaryWeLl;

  /// No description provided for @sendLink.
  ///
  /// In en, this message translates to:
  /// **'send the link'**
  String get sendLink;

  /// No description provided for @iAlreadyHaveLink.
  ///
  /// In en, this message translates to:
  /// **'i already have a link'**
  String get iAlreadyHaveLink;

  /// No description provided for @iHaveLink.
  ///
  /// In en, this message translates to:
  /// **'i have the link'**
  String get iHaveLink;

  /// No description provided for @checkInbox.
  ///
  /// In en, this message translates to:
  /// **'check your inbox'**
  String get checkInbox;

  /// No description provided for @theLinkWorksOneHourNothing.
  ///
  /// In en, this message translates to:
  /// **'the link works for one hour. nothing has changed until you use it'**
  String get theLinkWorksOneHourNothing;

  /// No description provided for @backSign.
  ///
  /// In en, this message translates to:
  /// **'back to sign in'**
  String get backSign;

  /// No description provided for @thatDoesnTLookLikeEmail.
  ///
  /// In en, this message translates to:
  /// **'that doesn\'t look like an email address'**
  String get thatDoesnTLookLikeEmail;

  /// No description provided for @setNewPassword.
  ///
  /// In en, this message translates to:
  /// **'set a new password'**
  String get setNewPassword;

  /// No description provided for @codeFromEmail.
  ///
  /// In en, this message translates to:
  /// **'code from the email'**
  String get codeFromEmail;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'new password'**
  String get newPassword;

  /// No description provided for @repeatNewPassword.
  ///
  /// In en, this message translates to:
  /// **'repeat the new password'**
  String get repeatNewPassword;

  /// No description provided for @pasteCodeFromEmailFirst.
  ///
  /// In en, this message translates to:
  /// **'paste the code from your email first'**
  String get pasteCodeFromEmailFirst;

  /// No description provided for @passwordNeedsLeast6Characters.
  ///
  /// In en, this message translates to:
  /// **'password needs at least 6 characters'**
  String get passwordNeedsLeast6Characters;

  /// No description provided for @theTwoPasswordsDonTMatch.
  ///
  /// In en, this message translates to:
  /// **'the two passwords don\'t match'**
  String get theTwoPasswordsDonTMatch;

  /// No description provided for @saveNewPassword.
  ///
  /// In en, this message translates to:
  /// **'save the new password'**
  String get saveNewPassword;

  /// No description provided for @thisSignsOutEveryDeviceSign.
  ///
  /// In en, this message translates to:
  /// **'this signs you out on every device — sign in again with the new password'**
  String get thisSignsOutEveryDeviceSign;

  /// No description provided for @yourSessionEndedPleaseSignAgain.
  ///
  /// In en, this message translates to:
  /// **'your session ended — please sign in again'**
  String get yourSessionEndedPleaseSignAgain;

  /// No description provided for @emailPasswordBlockedAccountsDownloadingDeleting.
  ///
  /// In en, this message translates to:
  /// **'email, password, blocked accounts, downloading or deleting everything'**
  String get emailPasswordBlockedAccountsDownloadingDeleting;

  /// No description provided for @gettingBack.
  ///
  /// In en, this message translates to:
  /// **'getting back in'**
  String get gettingBack;

  /// No description provided for @people.
  ///
  /// In en, this message translates to:
  /// **'people'**
  String get people;

  /// No description provided for @yourData.
  ///
  /// In en, this message translates to:
  /// **'your data'**
  String get yourData;

  /// No description provided for @addRecoveryEmail.
  ///
  /// In en, this message translates to:
  /// **'add a recovery email'**
  String get addRecoveryEmail;

  /// No description provided for @withoutOneForgottenPasswordMeansDiary.
  ///
  /// In en, this message translates to:
  /// **'without one, a forgotten password means the diary is gone'**
  String get withoutOneForgottenPasswordMeansDiary;

  /// No description provided for @confirmedCanRecoverAccount.
  ///
  /// In en, this message translates to:
  /// **'confirmed — you can recover your account with it'**
  String get confirmedCanRecoverAccount;

  /// No description provided for @notConfirmedYetTapSendLink.
  ///
  /// In en, this message translates to:
  /// **'not confirmed yet — tap to send the link again'**
  String get notConfirmedYetTapSendLink;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'change password'**
  String get changePassword;

  /// No description provided for @signsOutEveryOtherDevice.
  ///
  /// In en, this message translates to:
  /// **'signs out every other device'**
  String get signsOutEveryOtherDevice;

  /// No description provided for @whereReSigned.
  ///
  /// In en, this message translates to:
  /// **'where you\'re signed in'**
  String get whereReSigned;

  /// No description provided for @blockedAccounts.
  ///
  /// In en, this message translates to:
  /// **'blocked accounts'**
  String get blockedAccounts;

  /// No description provided for @theyCanTSeeCanT.
  ///
  /// In en, this message translates to:
  /// **'they can\'t see you, and you can\'t see them'**
  String get theyCanTSeeCanT;

  /// No description provided for @downloadEverything.
  ///
  /// In en, this message translates to:
  /// **'download everything'**
  String get downloadEverything;

  /// No description provided for @everyEveningListRatingOneFile.
  ///
  /// In en, this message translates to:
  /// **'every evening, list and rating, as one file you keep'**
  String get everyEveningListRatingOneFile;

  /// No description provided for @yourDiaryHasNoWayBack.
  ///
  /// In en, this message translates to:
  /// **'your diary has no way back in. add an email and a forgotten password stops being the end of it'**
  String get yourDiaryHasNoWayBack;

  /// No description provided for @tanMyDiary.
  ///
  /// In en, this message translates to:
  /// **'tanè — my diary'**
  String get tanMyDiary;

  /// No description provided for @recoveryEmail.
  ///
  /// In en, this message translates to:
  /// **'recovery email'**
  String get recoveryEmail;

  /// No description provided for @weLlSendLinkConfirmPassword.
  ///
  /// In en, this message translates to:
  /// **'we\'ll send a link to confirm it. your password is needed because this address can be used to get into your account'**
  String get weLlSendLinkConfirmPassword;

  /// No description provided for @yourPassword.
  ///
  /// In en, this message translates to:
  /// **'your password'**
  String get yourPassword;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'current password'**
  String get currentPassword;

  /// No description provided for @everyOtherDeviceSignedOutOne.
  ///
  /// In en, this message translates to:
  /// **'every other device is signed out. this one stays signed in'**
  String get everyOtherDeviceSignedOutOne;

  /// No description provided for @passwordChanged.
  ///
  /// In en, this message translates to:
  /// **'password changed'**
  String get passwordChanged;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'delete account'**
  String get deleteAccount;

  /// No description provided for @youHave30DaysChangeMind.
  ///
  /// In en, this message translates to:
  /// **'you have 30 days to change your mind'**
  String get youHave30DaysChangeMind;

  /// No description provided for @everythingGoesEveryEveningLoggedEvery.
  ///
  /// In en, this message translates to:
  /// **'everything goes: every evening you logged, every list, every rating. you have 30 days to change your mind — signing in before then brings it all back'**
  String get everythingGoesEveryEveningLoggedEvery;

  /// No description provided for @downloadFirst.
  ///
  /// In en, this message translates to:
  /// **'download it first'**
  String get downloadFirst;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'confirm with your password'**
  String get confirmPassword;

  /// No description provided for @anythingDLikeUsKnowOptional.
  ///
  /// In en, this message translates to:
  /// **'anything you\'d like us to know? (optional)'**
  String get anythingDLikeUsKnowOptional;

  /// No description provided for @deleteMyAccount.
  ///
  /// In en, this message translates to:
  /// **'delete my account'**
  String get deleteMyAccount;

  /// No description provided for @yourAccountDeleted.
  ///
  /// In en, this message translates to:
  /// **'your account is deleted'**
  String get yourAccountDeleted;

  /// No description provided for @understood.
  ///
  /// In en, this message translates to:
  /// **'understood'**
  String get understood;

  /// No description provided for @unknownDevice.
  ///
  /// In en, this message translates to:
  /// **'unknown device'**
  String get unknownDevice;

  /// No description provided for @signedOut.
  ///
  /// In en, this message translates to:
  /// **'signed out'**
  String get signedOut;

  /// No description provided for @lastUsed.
  ///
  /// In en, this message translates to:
  /// **'last used'**
  String get lastUsed;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'active'**
  String get active;

  /// No description provided for @signOutEverywhereElse.
  ///
  /// In en, this message translates to:
  /// **'sign out everywhere else'**
  String get signOutEverywhereElse;

  /// No description provided for @thisDeviceStaysSignedEveryOther.
  ///
  /// In en, this message translates to:
  /// **'this device stays signed in. every other one has to sign in again'**
  String get thisDeviceStaysSignedEveryOther;

  /// No description provided for @block.
  ///
  /// In en, this message translates to:
  /// **'block'**
  String get block;

  /// No description provided for @unblock.
  ///
  /// In en, this message translates to:
  /// **'unblock'**
  String get unblock;

  /// No description provided for @nobodyBlocked.
  ///
  /// In en, this message translates to:
  /// **'nobody blocked'**
  String get nobodyBlocked;

  /// No description provided for @youCanBlockAnyoneFromTheir.
  ///
  /// In en, this message translates to:
  /// **'you can block anyone from their profile, any time, without saying why'**
  String get youCanBlockAnyoneFromTheir;

  /// No description provided for @theyCanTSeeProfileEvenings.
  ///
  /// In en, this message translates to:
  /// **'they can\'t see your profile, your evenings, or reach you — and you won\'t see them anywhere either'**
  String get theyCanTSeeProfileEvenings;

  /// No description provided for @unblockingDoesnTMakeFriendsAgain.
  ///
  /// In en, this message translates to:
  /// **'unblocking doesn\'t make you friends again — that has to be asked for'**
  String get unblockingDoesnTMakeFriendsAgain;

  /// No description provided for @theyWonTAbleSeeProfile.
  ///
  /// In en, this message translates to:
  /// **'they won\'t be able to see your profile or your evenings, or reach you — and you won\'t see them anywhere. they\'re never told.'**
  String get theyWonTAbleSeeProfile;

  /// No description provided for @report.
  ///
  /// In en, this message translates to:
  /// **'report'**
  String get report;

  /// No description provided for @aPersonReadsEveryReportWithin.
  ///
  /// In en, this message translates to:
  /// **'a person reads every report, within 24 hours'**
  String get aPersonReadsEveryReportWithin;

  /// No description provided for @pickReasonFirst.
  ///
  /// In en, this message translates to:
  /// **'pick a reason first'**
  String get pickReasonFirst;

  /// No description provided for @anythingElseWeShouldKnowOptional.
  ///
  /// In en, this message translates to:
  /// **'anything else we should know? (optional)'**
  String get anythingElseWeShouldKnowOptional;

  /// No description provided for @alsoBlockThemStraightAway.
  ///
  /// In en, this message translates to:
  /// **'also block them, straight away'**
  String get alsoBlockThemStraightAway;

  /// No description provided for @sendReport.
  ///
  /// In en, this message translates to:
  /// **'send the report'**
  String get sendReport;

  /// No description provided for @thankWeRe.
  ///
  /// In en, this message translates to:
  /// **'thank you — we\'re on it'**
  String get thankWeRe;

  /// No description provided for @someoneReadsWithin24Hours.
  ///
  /// In en, this message translates to:
  /// **'someone reads this within 24 hours'**
  String get someoneReadsWithin24Hours;

  /// No description provided for @someoneReadsWithin24HoursMeantime.
  ///
  /// In en, this message translates to:
  /// **'someone reads this within 24 hours. in the meantime they can\'t reach you'**
  String get someoneReadsWithin24HoursMeantime;

  /// No description provided for @harassmentBullying.
  ///
  /// In en, this message translates to:
  /// **'harassment or bullying'**
  String get harassmentBullying;

  /// No description provided for @hateSpeech.
  ///
  /// In en, this message translates to:
  /// **'hate speech'**
  String get hateSpeech;

  /// No description provided for @sexualContent.
  ///
  /// In en, this message translates to:
  /// **'sexual content'**
  String get sexualContent;

  /// No description provided for @violenceCruelty.
  ///
  /// In en, this message translates to:
  /// **'violence or cruelty'**
  String get violenceCruelty;

  /// No description provided for @spamAdvertising.
  ///
  /// In en, this message translates to:
  /// **'spam or advertising'**
  String get spamAdvertising;

  /// No description provided for @pretendingSomeoneElse.
  ///
  /// In en, this message translates to:
  /// **'pretending to be someone else'**
  String get pretendingSomeoneElse;

  /// No description provided for @selfHarm.
  ///
  /// In en, this message translates to:
  /// **'self-harm'**
  String get selfHarm;

  /// No description provided for @childSafety.
  ///
  /// In en, this message translates to:
  /// **'child safety'**
  String get childSafety;

  /// No description provided for @somethingElse.
  ///
  /// In en, this message translates to:
  /// **'something else'**
  String get somethingElse;

  /// No description provided for @peopleCanFindMeByMy.
  ///
  /// In en, this message translates to:
  /// **'people can find me by my username'**
  String get peopleCanFindMeByMy;

  /// No description provided for @turningOffKeepsEveryFriendAlready.
  ///
  /// In en, this message translates to:
  /// **'turning this off keeps every friend you already have — only search stops finding you'**
  String get turningOffKeepsEveryFriendAlready;

  /// No description provided for @typeLeast3LettersTheirUsername.
  ///
  /// In en, this message translates to:
  /// **'type at least 3 letters of their username'**
  String get typeLeast3LettersTheirUsername;

  /// No description provided for @termsUse.
  ///
  /// In en, this message translates to:
  /// **'terms of use'**
  String get termsUse;

  /// No description provided for @readTerms.
  ///
  /// In en, this message translates to:
  /// **'read the terms'**
  String get readTerms;

  /// No description provided for @creatingDiaryMeansAgreeingTerms.
  ///
  /// In en, this message translates to:
  /// **'creating a diary means agreeing to the terms'**
  String get creatingDiaryMeansAgreeingTerms;

  /// No description provided for @iAgree.
  ///
  /// In en, this message translates to:
  /// **'i agree'**
  String get iAgree;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'email'**
  String get email;

  /// No description provided for @timeBudget40Min.
  ///
  /// In en, this message translates to:
  /// **'40 min'**
  String get timeBudget40Min;

  /// No description provided for @timeBudgetHour.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get timeBudgetHour;

  /// No description provided for @timeBudgetHourAndHalf.
  ///
  /// In en, this message translates to:
  /// **'1½ hours'**
  String get timeBudgetHourAndHalf;

  /// No description provided for @timeBudgetWholeEvening.
  ///
  /// In en, this message translates to:
  /// **'all evening'**
  String get timeBudgetWholeEvening;

  /// No description provided for @timeBannerGotItYouHave.
  ///
  /// In en, this message translates to:
  /// **'got it — you have'**
  String get timeBannerGotItYouHave;

  /// No description provided for @timeBannerYouHave.
  ///
  /// In en, this message translates to:
  /// **'you have'**
  String get timeBannerYouHave;

  /// No description provided for @timeShapeEpisodeOrTwo.
  ///
  /// In en, this message translates to:
  /// **'enough for an episode or two'**
  String get timeShapeEpisodeOrTwo;

  /// No description provided for @timeShapeWholeFilm.
  ///
  /// In en, this message translates to:
  /// **'enough for a whole film'**
  String get timeShapeWholeFilm;

  /// No description provided for @timeShapeEpisodeOrShortFilm.
  ///
  /// In en, this message translates to:
  /// **'an episode or a short film'**
  String get timeShapeEpisodeOrShortFilm;

  /// No description provided for @timeRelaxedNothingThatShort.
  ///
  /// In en, this message translates to:
  /// **'nothing that short turned up — showing the best there is'**
  String get timeRelaxedNothingThatShort;

  /// No description provided for @taneIsThinking.
  ///
  /// In en, this message translates to:
  /// **'tanè is thinking'**
  String get taneIsThinking;

  /// No description provided for @taneThinkReadingWhatYouWrote.
  ///
  /// In en, this message translates to:
  /// **'reading what you wrote'**
  String get taneThinkReadingWhatYouWrote;

  /// No description provided for @taneThinkCatchingTheMood.
  ///
  /// In en, this message translates to:
  /// **'catching the mood'**
  String get taneThinkCatchingTheMood;

  /// No description provided for @taneThinkThinkingItOver.
  ///
  /// In en, this message translates to:
  /// **'thinking it over'**
  String get taneThinkThinkingItOver;

  /// No description provided for @taneThinkHmmLetMeThink.
  ///
  /// In en, this message translates to:
  /// **'hmm, let me think'**
  String get taneThinkHmmLetMeThink;

  /// No description provided for @taneThinkGardenInBloom.
  ///
  /// In en, this message translates to:
  /// **'looking for what\'s in bloom'**
  String get taneThinkGardenInBloom;

  /// No description provided for @taneThinkCoachTimetable.
  ///
  /// In en, this message translates to:
  /// **'checking the timetable'**
  String get taneThinkCoachTimetable;

  /// No description provided for @taneThinkTicketTearOff.
  ///
  /// In en, this message translates to:
  /// **'tearing off the right ticket'**
  String get taneThinkTicketTearOff;

  /// No description provided for @taneThinkShuttleOrbit.
  ///
  /// In en, this message translates to:
  /// **'scanning the orbit'**
  String get taneThinkShuttleOrbit;

  /// No description provided for @taneThinkCountingMinutes.
  ///
  /// In en, this message translates to:
  /// **'counting the minutes'**
  String get taneThinkCountingMinutes;

  /// No description provided for @taneThinkCheckingRuntimes.
  ///
  /// In en, this message translates to:
  /// **'checking runtimes'**
  String get taneThinkCheckingRuntimes;

  /// No description provided for @taneThinkWeighingCandidates.
  ///
  /// In en, this message translates to:
  /// **'weighing the candidates'**
  String get taneThinkWeighingCandidates;

  /// No description provided for @taneThinkPickingBestFew.
  ///
  /// In en, this message translates to:
  /// **'picking the best few'**
  String get taneThinkPickingBestFew;

  /// No description provided for @taneThinkStillLooking.
  ///
  /// In en, this message translates to:
  /// **'still looking'**
  String get taneThinkStillLooking;

  /// No description provided for @taneThinkGoodOnesTakeAMoment.
  ///
  /// In en, this message translates to:
  /// **'good ones take a moment'**
  String get taneThinkGoodOnesTakeAMoment;

  /// No description provided for @taneThinkHereYouGo.
  ///
  /// In en, this message translates to:
  /// **'here you go'**
  String get taneThinkHereYouGo;

  /// No description provided for @planWhen.
  ///
  /// In en, this message translates to:
  /// **'when?'**
  String get planWhen;

  /// No description provided for @planGetYourTicket.
  ///
  /// In en, this message translates to:
  /// **'get your ticket'**
  String get planGetYourTicket;

  /// No description provided for @planNoExactTime.
  ///
  /// In en, this message translates to:
  /// **'no exact time — tap to pick one'**
  String get planNoExactTime;

  /// No description provided for @planCodesAre6Characters.
  ///
  /// In en, this message translates to:
  /// **'codes are 6 characters'**
  String get planCodesAre6Characters;

  /// No description provided for @inviteAction.
  ///
  /// In en, this message translates to:
  /// **'invite'**
  String get inviteAction;

  /// No description provided for @togetherGatheringCards.
  ///
  /// In en, this message translates to:
  /// **'gathering cards…'**
  String get togetherGatheringCards;

  /// No description provided for @togetherSettingUpSession.
  ///
  /// In en, this message translates to:
  /// **'setting up a session…'**
  String get togetherSettingUpSession;

  /// No description provided for @togetherItsAMatch.
  ///
  /// In en, this message translates to:
  /// **'it\'s a match!'**
  String get togetherItsAMatch;

  /// No description provided for @togetherPartnerIsHere.
  ///
  /// In en, this message translates to:
  /// **'is here'**
  String get togetherPartnerIsHere;

  /// No description provided for @togetherLetsSwipe.
  ///
  /// In en, this message translates to:
  /// **'let\'s swipe together'**
  String get togetherLetsSwipe;

  /// No description provided for @voteYouBothSaidYes.
  ///
  /// In en, this message translates to:
  /// **'you both said yes'**
  String get voteYouBothSaidYes;

  /// No description provided for @voteEveryoneSaidYes.
  ///
  /// In en, this message translates to:
  /// **'everyone said yes'**
  String get voteEveryoneSaidYes;

  /// No description provided for @voteYouBothSaidYesPlanned.
  ///
  /// In en, this message translates to:
  /// **'you both said yes — it\'s on your planned together list now.'**
  String get voteYouBothSaidYesPlanned;

  /// No description provided for @voteEveryoneSaidYesPlanned.
  ///
  /// In en, this message translates to:
  /// **'everyone said yes — it\'s on your planned together list now.'**
  String get voteEveryoneSaidYesPlanned;

  /// No description provided for @importErrorMatch.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t match those just now — try again in a moment'**
  String get importErrorMatch;

  /// No description provided for @importErrorSave.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t save those just now — try again'**
  String get importErrorSave;

  /// No description provided for @importReadingList.
  ///
  /// In en, this message translates to:
  /// **'reading your list'**
  String get importReadingList;

  /// No description provided for @importMatchingEach.
  ///
  /// In en, this message translates to:
  /// **'matching each title'**
  String get importMatchingEach;

  /// No description provided for @importSortingShelves.
  ///
  /// In en, this message translates to:
  /// **'sorting them onto the right shelves'**
  String get importSortingShelves;

  /// No description provided for @importBigLists.
  ///
  /// In en, this message translates to:
  /// **'big lists take a moment'**
  String get importBigLists;

  /// No description provided for @importStillMatching.
  ///
  /// In en, this message translates to:
  /// **'still matching'**
  String get importStillMatching;

  /// No description provided for @anonymousUsageStatistics.
  ///
  /// In en, this message translates to:
  /// **'anonymous usage statistics'**
  String get anonymousUsageStatistics;

  /// No description provided for @anonymousUsageStatisticsHint.
  ///
  /// In en, this message translates to:
  /// **'helps us see which screens get used and which ones confuse people. only what happened is sent — never titles, notes, what you search for, or anything you type. turning it off also forgets this device.'**
  String get anonymousUsageStatisticsHint;

  /// No description provided for @rouletteReadyWhenYouAre.
  ///
  /// In en, this message translates to:
  /// **'ready when you are'**
  String get rouletteReadyWhenYouAre;

  /// No description provided for @savedInYourDiary.
  ///
  /// In en, this message translates to:
  /// **'in your diary'**
  String get savedInYourDiary;

  /// No description provided for @savedLoggedTogether.
  ///
  /// In en, this message translates to:
  /// **'logged together'**
  String get savedLoggedTogether;

  /// No description provided for @savedOnYourList.
  ///
  /// In en, this message translates to:
  /// **'on your list'**
  String get savedOnYourList;

  /// No description provided for @savedPlannedTogether.
  ///
  /// In en, this message translates to:
  /// **'planned together'**
  String get savedPlannedTogether;

  /// No description provided for @couldntAcceptJustNow.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t accept that just now — try again'**
  String get couldntAcceptJustNow;

  /// No description provided for @searchStartTyping.
  ///
  /// In en, this message translates to:
  /// **'or start typing to look through tanè\'s catalog'**
  String get searchStartTyping;

  /// No description provided for @searchNothingInCatalog.
  ///
  /// In en, this message translates to:
  /// **'nothing turned up for that in the catalog itself'**
  String get searchNothingInCatalog;

  /// No description provided for @threeMonths.
  ///
  /// In en, this message translates to:
  /// **'three months'**
  String get threeMonths;

  /// No description provided for @restorePurchases.
  ///
  /// In en, this message translates to:
  /// **'restore purchases'**
  String get restorePurchases;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'privacy policy'**
  String get privacyPolicy;

  /// No description provided for @startYourFreeTrial.
  ///
  /// In en, this message translates to:
  /// **'start your free trial'**
  String get startYourFreeTrial;

  /// No description provided for @freeDaysChip.
  ///
  /// In en, this message translates to:
  /// **'free days'**
  String get freeDaysChip;

  /// No description provided for @unlimitedAsksEveryNight.
  ///
  /// In en, this message translates to:
  /// **'unlimited asks, every night'**
  String get unlimitedAsksEveryNight;

  /// No description provided for @unlimitedAsksTogether.
  ///
  /// In en, this message translates to:
  /// **'unlimited asks, together'**
  String get unlimitedAsksTogether;

  /// No description provided for @unlimitedAsksFromDayOne.
  ///
  /// In en, this message translates to:
  /// **'unlimited asks, from day one'**
  String get unlimitedAsksFromDayOne;

  /// No description provided for @unlimitedAsksTogetherFromDayOne.
  ///
  /// In en, this message translates to:
  /// **'unlimited asks, together, from day one'**
  String get unlimitedAsksTogetherFromDayOne;

  /// No description provided for @yourFreeTrialStarted.
  ///
  /// In en, this message translates to:
  /// **'your free trial has started'**
  String get yourFreeTrialStarted;

  /// No description provided for @trialDaysNoCardCancelAnytime.
  ///
  /// In en, this message translates to:
  /// **'days · no card needed · cancel anytime'**
  String get trialDaysNoCardCancelAnytime;

  /// No description provided for @thenPlanAboveNoCardNow.
  ///
  /// In en, this message translates to:
  /// **'for the plan above · no card needed now'**
  String get thenPlanAboveNoCardNow;

  /// No description provided for @premiumRestored.
  ///
  /// In en, this message translates to:
  /// **'premium restored'**
  String get premiumRestored;

  /// No description provided for @youreAlreadyAllSet.
  ///
  /// In en, this message translates to:
  /// **'you\'re already all set'**
  String get youreAlreadyAllSet;

  /// No description provided for @nothingToRestore.
  ///
  /// In en, this message translates to:
  /// **'nothing to restore on this account'**
  String get nothingToRestore;

  /// No description provided for @couldntCheckRightNow.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t check right now — try again in a moment'**
  String get couldntCheckRightNow;

  /// No description provided for @trailerOnYourPlan.
  ///
  /// In en, this message translates to:
  /// **'on your plan'**
  String get trailerOnYourPlan;

  /// No description provided for @peopleSimilarTaste.
  ///
  /// In en, this message translates to:
  /// **'people with a similar taste'**
  String get peopleSimilarTaste;

  /// No description provided for @basedWhatJustPickedSayHi.
  ///
  /// In en, this message translates to:
  /// **'based on what you just picked — say hi now, or find them later on the friends screen.'**
  String get basedWhatJustPickedSayHi;

  /// No description provided for @notEnoughGoYetPickFavorite.
  ///
  /// In en, this message translates to:
  /// **'not enough to go on yet — pick a favorite or two above, or check the friends screen again later'**
  String get notEnoughGoYetPickFavorite;

  /// No description provided for @eveningsWatchedTogether.
  ///
  /// In en, this message translates to:
  /// **'evenings watched together'**
  String get eveningsWatchedTogether;

  /// No description provided for @challengesCollected.
  ///
  /// In en, this message translates to:
  /// **'challenges collected'**
  String get challengesCollected;

  /// No description provided for @cardsShared.
  ///
  /// In en, this message translates to:
  /// **'cards shared'**
  String get cardsShared;

  /// No description provided for @collected.
  ///
  /// In en, this message translates to:
  /// **'collected'**
  String get collected;

  /// No description provided for @sharedCount.
  ///
  /// In en, this message translates to:
  /// **'shared'**
  String get sharedCount;

  /// No description provided for @cardShareXpHint.
  ///
  /// In en, this message translates to:
  /// **'a card earns xp the first time it\'s shared — and only a couple of cards a day count'**
  String get cardShareXpHint;

  /// No description provided for @poolQueuedTitle.
  ///
  /// In en, this message translates to:
  /// **'what you each queued'**
  String get poolQueuedTitle;

  /// No description provided for @poolQueuedBlurb.
  ///
  /// In en, this message translates to:
  /// **'the titles on each of your plan-to-watch shelves'**
  String get poolQueuedBlurb;

  /// No description provided for @poolAgreedTitle.
  ///
  /// In en, this message translates to:
  /// **'already agreed together'**
  String get poolAgreedTitle;

  /// No description provided for @poolAgreedBlurb.
  ///
  /// In en, this message translates to:
  /// **'what\'s already on your shared list'**
  String get poolAgreedBlurb;

  /// No description provided for @poolBothTitle.
  ///
  /// In en, this message translates to:
  /// **'both of those'**
  String get poolBothTitle;

  /// No description provided for @poolBothBlurb.
  ///
  /// In en, this message translates to:
  /// **'your shelves and your shared list, together'**
  String get poolBothBlurb;

  /// No description provided for @poolCatalogTitle.
  ///
  /// In en, this message translates to:
  /// **'everything'**
  String get poolCatalogTitle;

  /// No description provided for @poolCatalogBlurb.
  ///
  /// In en, this message translates to:
  /// **'the whole catalog — even what nobody\'s queued yet'**
  String get poolCatalogBlurb;

  /// No description provided for @addAStatus.
  ///
  /// In en, this message translates to:
  /// **'add a status'**
  String get addAStatus;

  /// No description provided for @reached.
  ///
  /// In en, this message translates to:
  /// **'reached'**
  String get reached;

  /// No description provided for @badgeUnlocked.
  ///
  /// In en, this message translates to:
  /// **'badge unlocked'**
  String get badgeUnlocked;

  /// No description provided for @unlocksABadge.
  ///
  /// In en, this message translates to:
  /// **'unlocks a badge'**
  String get unlocksABadge;

  /// No description provided for @ratingShownAsLocked.
  ///
  /// In en, this message translates to:
  /// **'rating shown as locked?'**
  String get ratingShownAsLocked;

  /// No description provided for @ratingHiddenExplainer.
  ///
  /// In en, this message translates to:
  /// **'Your partner already rated it, but that rating stays hidden from you until you rate it too — so their opinion never colors yours. Curious sooner? Tap the lock to reveal it early for a few sincerity points.'**
  String get ratingHiddenExplainer;

  /// No description provided for @youReLinkedGoUnlimitedTogether.
  ///
  /// In en, this message translates to:
  /// **'you\'re linked — go unlimited together'**
  String get youReLinkedGoUnlimitedTogether;

  /// No description provided for @sharedWatchListNoLimitForBoth.
  ///
  /// In en, this message translates to:
  /// **'when one of you has premium, your shared watch list has no limit — for both of you'**
  String get sharedWatchListNoLimitForBoth;

  /// No description provided for @trialFreePeriod.
  ///
  /// In en, this message translates to:
  /// **'free period'**
  String get trialFreePeriod;

  /// No description provided for @trialHoursLeft.
  ///
  /// In en, this message translates to:
  /// **'h left'**
  String get trialHoursLeft;

  /// No description provided for @trialDaysLeft.
  ///
  /// In en, this message translates to:
  /// **'d left'**
  String get trialDaysLeft;

  /// No description provided for @trialLessThanHourLeft.
  ///
  /// In en, this message translates to:
  /// **'less than an hour left'**
  String get trialLessThanHourLeft;

  /// No description provided for @trialBringUnlimitedBack.
  ///
  /// In en, this message translates to:
  /// **'bring unlimited back whenever you like'**
  String get trialBringUnlimitedBack;

  /// No description provided for @trialKeepUnlimited.
  ///
  /// In en, this message translates to:
  /// **'keep everything unlimited'**
  String get trialKeepUnlimited;

  /// No description provided for @trialEnded.
  ///
  /// In en, this message translates to:
  /// **'your free period has ended'**
  String get trialEnded;

  /// No description provided for @trialAlmostOver.
  ///
  /// In en, this message translates to:
  /// **'your free period is almost over'**
  String get trialAlmostOver;

  /// No description provided for @trialEndedSub.
  ///
  /// In en, this message translates to:
  /// **'your entries and lists are safe — only the limits are back. bring unlimited back whenever you like'**
  String get trialEndedSub;

  /// No description provided for @trialAlmostOverSub.
  ///
  /// In en, this message translates to:
  /// **'no card was linked, so nothing is charged on its own — pick a plan to keep everything unlimited'**
  String get trialAlmostOverSub;

  /// No description provided for @trialNoCardNoCharge.
  ///
  /// In en, this message translates to:
  /// **'no card is linked — nothing is charged by itself'**
  String get trialNoCardNoCharge;

  /// No description provided for @trialBackOnFree.
  ///
  /// In en, this message translates to:
  /// **'back on the free plan'**
  String get trialBackOnFree;

  /// No description provided for @trialWhenItEnds.
  ///
  /// In en, this message translates to:
  /// **'when it ends, you\'re on the free plan'**
  String get trialWhenItEnds;

  /// No description provided for @trialLimitAsks.
  ///
  /// In en, this message translates to:
  /// **'Teamira questions a month'**
  String get trialLimitAsks;

  /// No description provided for @trialLimitFavorites.
  ///
  /// In en, this message translates to:
  /// **'favorite titles kept on the free plan'**
  String get trialLimitFavorites;

  /// No description provided for @trialLimitLists.
  ///
  /// In en, this message translates to:
  /// **'custom lists'**
  String get trialLimitLists;

  /// No description provided for @trialEntriesStay.
  ///
  /// In en, this message translates to:
  /// **'your entries, ratings and lists stay exactly as they are'**
  String get trialEntriesStay;

  /// No description provided for @trialThingsDone.
  ///
  /// In en, this message translates to:
  /// **'things you did during the free period'**
  String get trialThingsDone;

  /// No description provided for @trialSettingsOn.
  ///
  /// In en, this message translates to:
  /// **'free period is on'**
  String get trialSettingsOn;

  /// No description provided for @trialSettingsTap.
  ///
  /// In en, this message translates to:
  /// **'tap to keep unlimited after it ends'**
  String get trialSettingsTap;

  /// No description provided for @familyUnlimitedNow.
  ///
  /// In en, this message translates to:
  /// **'your whole circle is unlimited now — enjoy watching together'**
  String get familyUnlimitedNow;

  /// No description provided for @switchToThisPlanFor.
  ///
  /// In en, this message translates to:
  /// **'switch to this plan for'**
  String get switchToThisPlanFor;

  /// No description provided for @familyHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'one plan for up to four of you — a shared evening with no limits for anyone'**
  String get familyHeroSubtitle;

  /// No description provided for @familyAndFriends.
  ///
  /// In en, this message translates to:
  /// **'family & friends'**
  String get familyAndFriends;

  /// No description provided for @familySubtitle.
  ///
  /// In en, this message translates to:
  /// **'up to four of you, one plan'**
  String get familySubtitle;

  /// No description provided for @upToFourBadge.
  ///
  /// In en, this message translates to:
  /// **'up to 4'**
  String get upToFourBadge;

  /// No description provided for @planCoversTwo.
  ///
  /// In en, this message translates to:
  /// **'your plan covers two'**
  String get planCoversTwo;

  /// No description provided for @planCoversFour.
  ///
  /// In en, this message translates to:
  /// **'your plan covers four'**
  String get planCoversFour;

  /// No description provided for @coupleOutgrownMessage.
  ///
  /// In en, this message translates to:
  /// **'add a third person and the couple plan stops covering the other one — the family plan covers up to four'**
  String get coupleOutgrownMessage;

  /// No description provided for @familyOutgrownMessage.
  ///
  /// In en, this message translates to:
  /// **'add another person and the family plan stops covering the others — until someone leaves, only you keep premium'**
  String get familyOutgrownMessage;

  /// No description provided for @seeFamilyPlan.
  ///
  /// In en, this message translates to:
  /// **'see the family plan'**
  String get seeFamilyPlan;

  /// No description provided for @keepCircleAsIs.
  ///
  /// In en, this message translates to:
  /// **'keep the circle as it is'**
  String get keepCircleAsIs;

  /// No description provided for @addAnyway.
  ///
  /// In en, this message translates to:
  /// **'add anyway'**
  String get addAnyway;

  /// No description provided for @yourSubscription.
  ///
  /// In en, this message translates to:
  /// **'your subscription'**
  String get yourSubscription;

  /// No description provided for @welcomeBackOffer.
  ///
  /// In en, this message translates to:
  /// **'welcome back offer'**
  String get welcomeBackOffer;

  /// No description provided for @yourEntriesSafe.
  ///
  /// In en, this message translates to:
  /// **'your entries are safe'**
  String get yourEntriesSafe;

  /// No description provided for @pausedSeeSoon.
  ///
  /// In en, this message translates to:
  /// **'paused — see you soon'**
  String get pausedSeeSoon;

  /// No description provided for @subscriptionCancelled.
  ///
  /// In en, this message translates to:
  /// **'subscription cancelled'**
  String get subscriptionCancelled;

  /// No description provided for @welcomeBackYoursAgain.
  ///
  /// In en, this message translates to:
  /// **'welcome back — it is yours again'**
  String get welcomeBackYoursAgain;

  /// No description provided for @premiumBack.
  ///
  /// In en, this message translates to:
  /// **'premium is back'**
  String get premiumBack;

  /// No description provided for @resumeNow.
  ///
  /// In en, this message translates to:
  /// **'resume now'**
  String get resumeNow;

  /// No description provided for @theUnusedDaysBreakComeBack.
  ///
  /// In en, this message translates to:
  /// **'the unused days of the break come back to you, nothing is lost'**
  String get theUnusedDaysBreakComeBack;

  /// No description provided for @cancelSubscription.
  ///
  /// In en, this message translates to:
  /// **'cancel subscription'**
  String get cancelSubscription;

  /// No description provided for @onCouplePlanPartnerSSeat.
  ///
  /// In en, this message translates to:
  /// **'on a couple plan your partner’s seat follows yours'**
  String get onCouplePlanPartnerSSeat;

  /// No description provided for @onFamilyPlanOtherSeatsFollow.
  ///
  /// In en, this message translates to:
  /// **'on a family plan the other seats follow yours'**
  String get onFamilyPlanOtherSeatsFollow;

  /// No description provided for @theOtherSeatsEndTogetherYours.
  ///
  /// In en, this message translates to:
  /// **'the other seats end together with yours'**
  String get theOtherSeatsEndTogetherYours;

  /// No description provided for @onBreak.
  ///
  /// In en, this message translates to:
  /// **'on a break'**
  String get onBreak;

  /// No description provided for @back3.
  ///
  /// In en, this message translates to:
  /// **'back on'**
  String get back3;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'cancelled'**
  String get cancelled;

  /// No description provided for @premiumWorksUntil.
  ///
  /// In en, this message translates to:
  /// **'premium works until'**
  String get premiumWorksUntil;

  /// No description provided for @renews.
  ///
  /// In en, this message translates to:
  /// **'renews on'**
  String get renews;

  /// No description provided for @needBreather.
  ///
  /// In en, this message translates to:
  /// **'need a breather?'**
  String get needBreather;

  /// No description provided for @freeze.
  ///
  /// In en, this message translates to:
  /// **'freeze it for'**
  String get freeze;

  /// No description provided for @noPaymentTimeComesBackBy.
  ///
  /// In en, this message translates to:
  /// **'no payment for that time, it comes back by itself'**
  String get noPaymentTimeComesBackBy;

  /// No description provided for @pauseMonth.
  ///
  /// In en, this message translates to:
  /// **'pause for a month'**
  String get pauseMonth;

  /// No description provided for @changedMind.
  ///
  /// In en, this message translates to:
  /// **'changed your mind?'**
  String get changedMind;

  /// No description provided for @keepSubscriptionNothingChargedNow.
  ///
  /// In en, this message translates to:
  /// **'keep the subscription — nothing is charged now'**
  String get keepSubscriptionNothingChargedNow;

  /// No description provided for @keepMySubscription.
  ///
  /// In en, this message translates to:
  /// **'keep my subscription'**
  String get keepMySubscription;

  /// No description provided for @beforeGo.
  ///
  /// In en, this message translates to:
  /// **'before you go'**
  String get beforeGo;

  /// No description provided for @premiumKeepsWorkingUntilEndPeriod.
  ///
  /// In en, this message translates to:
  /// **'premium keeps working until the end of the period you paid for'**
  String get premiumKeepsWorkingUntilEndPeriod;

  /// No description provided for @whatMadeDecideOptional.
  ///
  /// In en, this message translates to:
  /// **'what made you decide? (optional)'**
  String get whatMadeDecideOptional;

  /// No description provided for @tooExpensive.
  ///
  /// In en, this message translates to:
  /// **'too expensive'**
  String get tooExpensive;

  /// No description provided for @notUsingEnough.
  ///
  /// In en, this message translates to:
  /// **'not using it enough'**
  String get notUsingEnough;

  /// No description provided for @missingSomething.
  ///
  /// In en, this message translates to:
  /// **'missing something'**
  String get missingSomething;

  /// No description provided for @justBreak.
  ///
  /// In en, this message translates to:
  /// **'just a break'**
  String get justBreak;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'other'**
  String get other;

  /// No description provided for @yourPartnerSSeatEndsTogether.
  ///
  /// In en, this message translates to:
  /// **'your partner’s seat ends together with yours'**
  String get yourPartnerSSeatEndsTogether;

  /// No description provided for @cancelEndPeriod.
  ///
  /// In en, this message translates to:
  /// **'cancel at the end of the period'**
  String get cancelEndPeriod;

  /// No description provided for @pauseInstead.
  ///
  /// In en, this message translates to:
  /// **'pause instead'**
  String get pauseInstead;

  /// No description provided for @noPaymentComesBackByItself.
  ///
  /// In en, this message translates to:
  /// **'no payment, comes back by itself'**
  String get noPaymentComesBackByItself;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'welcome back'**
  String get welcomeBack;

  /// No description provided for @yourEntriesListsSafePersonalOffer.
  ///
  /// In en, this message translates to:
  /// **'your entries and lists are safe — a personal offer just for you, until'**
  String get yourEntriesListsSafePersonalOffer;

  /// No description provided for @manageSubscription.
  ///
  /// In en, this message translates to:
  /// **'manage subscription'**
  String get manageSubscription;

  /// No description provided for @personalOffer.
  ///
  /// In en, this message translates to:
  /// **'personal offer'**
  String get personalOffer;

  /// No description provided for @appliedAutomatically.
  ///
  /// In en, this message translates to:
  /// **'applied automatically'**
  String get appliedAutomatically;

  /// No description provided for @welcomeBackOfferApplied.
  ///
  /// In en, this message translates to:
  /// **'welcome back offer applied'**
  String get welcomeBackOfferApplied;

  /// No description provided for @premiumBreak.
  ///
  /// In en, this message translates to:
  /// **'premium is on a break'**
  String get premiumBreak;

  /// No description provided for @subscriptionEndsSoon.
  ///
  /// In en, this message translates to:
  /// **'subscription ends soon'**
  String get subscriptionEndsSoon;

  /// No description provided for @pauseCancelChangePlan.
  ///
  /// In en, this message translates to:
  /// **'pause, cancel or change the plan'**
  String get pauseCancelChangePlan;

  /// No description provided for @aPersonalDiscountFewDaysOnly.
  ///
  /// In en, this message translates to:
  /// **'a personal discount, for a few days only'**
  String get aPersonalDiscountFewDaysOnly;

  /// No description provided for @kinopoiskLabel.
  ///
  /// In en, this message translates to:
  /// **'kinopoisk'**
  String get kinopoiskLabel;

  /// No description provided for @kinopoiskName.
  ///
  /// In en, this message translates to:
  /// **'Kinopoisk'**
  String get kinopoiskName;

  /// No description provided for @tonePositive.
  ///
  /// In en, this message translates to:
  /// **'positive'**
  String get tonePositive;

  /// No description provided for @toneNegative.
  ///
  /// In en, this message translates to:
  /// **'negative'**
  String get toneNegative;

  /// No description provided for @toneNeutral.
  ///
  /// In en, this message translates to:
  /// **'neutral'**
  String get toneNeutral;

  /// No description provided for @readInFullOn.
  ///
  /// In en, this message translates to:
  /// **'read in full on'**
  String get readInFullOn;

  /// No description provided for @reviewsOnHardcover.
  ///
  /// In en, this message translates to:
  /// **'reviews on Hardcover'**
  String get reviewsOnHardcover;

  /// No description provided for @reviewsProvidedByTmdbTraktKinopoisk.
  ///
  /// In en, this message translates to:
  /// **'Reviews provided by TMDB, Trakt and Kinopoisk (via PoiskKino)'**
  String get reviewsProvidedByTmdbTraktKinopoisk;

  /// No description provided for @forExactlyHowYourPointsAdd.
  ///
  /// In en, this message translates to:
  /// **'for exactly how your points add up, see your sincerity history'**
  String get forExactlyHowYourPointsAdd;

  /// No description provided for @yourActivity.
  ///
  /// In en, this message translates to:
  /// **'your activity'**
  String get yourActivity;

  /// No description provided for @pointsComeFromTheMilesYou.
  ///
  /// In en, this message translates to:
  /// **'points come from the miles you\'ve actually driven — logged evenings, reviews, rewatches, streaks, and genres explored'**
  String get pointsComeFromTheMilesYou;

  /// No description provided for @pointsComeFromWhatSActually.
  ///
  /// In en, this message translates to:
  /// **'points come from what\'s actually played on the reel — logged evenings, reviews, rewatches, streaks, and genres explored'**
  String get pointsComeFromWhatSActually;

  /// No description provided for @pointsComeFromWhatYouVe.
  ///
  /// In en, this message translates to:
  /// **'points come from what you\'ve actually launched — logged evenings, reviews, rewatches, streaks, and genres explored'**
  String get pointsComeFromWhatYouVe;

  /// No description provided for @pointsGrowFromWhatYouActually.
  ///
  /// In en, this message translates to:
  /// **'points grow from what you actually plant here — logged evenings, reviews, rewatches, streaks, and genres explored'**
  String get pointsGrowFromWhatYouActually;

  /// No description provided for @pointsLabel.
  ///
  /// In en, this message translates to:
  /// **'points'**
  String get pointsLabel;

  /// No description provided for @theFirstOne.
  ///
  /// In en, this message translates to:
  /// **'the first one'**
  String get theFirstOne;

  /// No description provided for @loggedYourFirstEveningTogether.
  ///
  /// In en, this message translates to:
  /// **'logged your first evening together'**
  String get loggedYourFirstEveningTogether;

  /// No description provided for @intoAHabit.
  ///
  /// In en, this message translates to:
  /// **'into a habit'**
  String get intoAHabit;

  /// No description provided for @tenEveningsTogether.
  ///
  /// In en, this message translates to:
  /// **'10 evenings together'**
  String get tenEveningsTogether;

  /// No description provided for @quarterCentury.
  ///
  /// In en, this message translates to:
  /// **'quarter century'**
  String get quarterCentury;

  /// No description provided for @twentyFiveEveningsTogether.
  ///
  /// In en, this message translates to:
  /// **'25 evenings together'**
  String get twentyFiveEveningsTogether;

  /// No description provided for @halfAHundred.
  ///
  /// In en, this message translates to:
  /// **'half a hundred'**
  String get halfAHundred;

  /// No description provided for @fiftyEveningsTogether.
  ///
  /// In en, this message translates to:
  /// **'50 evenings together'**
  String get fiftyEveningsTogether;

  /// No description provided for @aHundredNights.
  ///
  /// In en, this message translates to:
  /// **'a hundred nights'**
  String get aHundredNights;

  /// No description provided for @hundredEveningsTogether.
  ///
  /// In en, this message translates to:
  /// **'100 evenings together'**
  String get hundredEveningsTogether;

  /// No description provided for @wellRounded.
  ///
  /// In en, this message translates to:
  /// **'well-rounded'**
  String get wellRounded;

  /// No description provided for @watchedTogetherAcross5DifferentGenres.
  ///
  /// In en, this message translates to:
  /// **'watched together across 5+ different genres'**
  String get watchedTogetherAcross5DifferentGenres;

  /// No description provided for @threeInARow.
  ///
  /// In en, this message translates to:
  /// **'three in a row'**
  String get threeInARow;

  /// No description provided for @a3DayStreakTogether.
  ///
  /// In en, this message translates to:
  /// **'a 3-day streak together'**
  String get a3DayStreakTogether;

  /// No description provided for @aWeekStraight.
  ///
  /// In en, this message translates to:
  /// **'a week straight'**
  String get aWeekStraight;

  /// No description provided for @a7DayStreakTogether.
  ///
  /// In en, this message translates to:
  /// **'a 7-day streak together'**
  String get a7DayStreakTogether;

  /// No description provided for @oneMonthIn.
  ///
  /// In en, this message translates to:
  /// **'one month in'**
  String get oneMonthIn;

  /// No description provided for @thirtyDaysLinked.
  ///
  /// In en, this message translates to:
  /// **'30 days linked'**
  String get thirtyDaysLinked;

  /// No description provided for @aHundredDaysLinked.
  ///
  /// In en, this message translates to:
  /// **'a hundred days linked'**
  String get aHundredDaysLinked;

  /// No description provided for @hundredDaysLinked.
  ///
  /// In en, this message translates to:
  /// **'100 days linked'**
  String get hundredDaysLinked;

  /// No description provided for @aFullYear.
  ///
  /// In en, this message translates to:
  /// **'a full year'**
  String get aFullYear;

  /// No description provided for @aFullYearLinked.
  ///
  /// In en, this message translates to:
  /// **'a full year linked'**
  String get aFullYearLinked;

  /// Couple-facing wording ('ваш…', Russian-first partner screens look it up by that Russian text). Its English text equals the solo key's, so the Russian side deliberately loses the 'last key wins' tie to the solo wording ('твой…'): keep this key's name sorting BEFORE the solo key (generate_compat_layer.py sorts keys).
  ///
  /// In en, this message translates to:
  /// **'when you watch'**
  String get coupleWhenYouWatch;

  /// Couple-facing wording ('ваш…', Russian-first partner screens look it up by that Russian text). Its English text equals the solo key's, so the Russian side deliberately loses the 'last key wins' tie to the solo wording ('твой…'): keep this key's name sorting BEFORE the solo key (generate_compat_layer.py sorts keys).
  ///
  /// In en, this message translates to:
  /// **'your movie hour'**
  String get coupleYourMovieHour;

  /// Couple-facing wording ('ваш…', Russian-first partner screens look it up by that Russian text). Its English text equals the solo key's, so the Russian side deliberately loses the 'last key wins' tie to the solo wording ('твой…'): keep this key's name sorting BEFORE the solo key (generate_compat_layer.py sorts keys).
  ///
  /// In en, this message translates to:
  /// **'your film reel'**
  String get coupleYourFilmReel;

  /// Couple-facing wording ('ваш…', Russian-first partner screens look it up by that Russian text). Its English text equals the solo key's, so the Russian side deliberately loses the 'last key wins' tie to the solo wording ('твой…'): keep this key's name sorting BEFORE the solo key (generate_compat_layer.py sorts keys).
  ///
  /// In en, this message translates to:
  /// **'what era your movies are from'**
  String get coupleWhatEraYourMoviesAreFrom;

  /// No description provided for @whichDayIsYours.
  ///
  /// In en, this message translates to:
  /// **'which day is yours'**
  String get whichDayIsYours;

  /// No description provided for @yourArchetypeTogether.
  ///
  /// In en, this message translates to:
  /// **'your archetype, together'**
  String get yourArchetypeTogether;

  /// Couple-facing wording ('ваш…', Russian-first partner screens look it up by that Russian text). Its English text equals the solo key's, so the Russian side deliberately loses the 'last key wins' tie to the solo wording ('твой…'): keep this key's name sorting BEFORE the solo key (generate_compat_layer.py sorts keys).
  ///
  /// In en, this message translates to:
  /// **'your reviews'**
  String get coupleYourReviews;

  /// No description provided for @coViewRevealRatingTitle.
  ///
  /// In en, this message translates to:
  /// **'reveal the rating?'**
  String get coViewRevealRatingTitle;

  /// No description provided for @coViewRevealRatingBody.
  ///
  /// In en, this message translates to:
  /// **'already rated this title. take a look now — or rate it yourself first and earn points for your own opinion?'**
  String get coViewRevealRatingBody;

  /// No description provided for @coViewNudgePlanTitle.
  ///
  /// In en, this message translates to:
  /// **'remind about the plan?'**
  String get coViewNudgePlanTitle;

  /// No description provided for @coViewNudgePlanBody.
  ///
  /// In en, this message translates to:
  /// **'has been sitting untouched in your shared plans. send everyone one push reminder?'**
  String get coViewNudgePlanBody;

  /// No description provided for @coViewNudgeConfirm.
  ///
  /// In en, this message translates to:
  /// **'remind'**
  String get coViewNudgeConfirm;

  /// No description provided for @showcaseExtraSlot.
  ///
  /// In en, this message translates to:
  /// **'extra slot'**
  String get showcaseExtraSlot;

  /// No description provided for @showcaseExtraSlotTitle.
  ///
  /// In en, this message translates to:
  /// **'another slot in the showcase?'**
  String get showcaseExtraSlotTitle;

  /// No description provided for @showcaseExtraSlotBodyStart.
  ///
  /// In en, this message translates to:
  /// **'one-time and forever — you\'ll be able to show'**
  String get showcaseExtraSlotBodyStart;

  /// No description provided for @showcaseExtraSlotBodyMid.
  ///
  /// In en, this message translates to:
  /// **'awards instead of'**
  String get showcaseExtraSlotBodyMid;

  /// No description provided for @showcaseBuy.
  ///
  /// In en, this message translates to:
  /// **'buy'**
  String get showcaseBuy;

  /// No description provided for @sincerityExplainReturnDropped.
  ///
  /// In en, this message translates to:
  /// **'come back to something you dropped and finish it after all'**
  String get sincerityExplainReturnDropped;

  /// No description provided for @sincerityExplainRateOwnFirst.
  ///
  /// In en, this message translates to:
  /// **'rate a shared title yourself — without peeking at your partner\'s rating'**
  String get sincerityExplainRateOwnFirst;

  /// No description provided for @sincerityExplainPeekEarly.
  ///
  /// In en, this message translates to:
  /// **'open your partner\'s rating before rating the title yourself'**
  String get sincerityExplainPeekEarly;

  /// No description provided for @sincerityExplainPayOnce.
  ///
  /// In en, this message translates to:
  /// **'pay once — and a title in your plans never drains your points again'**
  String get sincerityExplainPayOnce;

  /// No description provided for @sincerityExplainBuySlot.
  ///
  /// In en, this message translates to:
  /// **'buy one more slot in your profile\'s awards showcase'**
  String get sincerityExplainBuySlot;

  /// No description provided for @sincerityExplainNudgePartner.
  ///
  /// In en, this message translates to:
  /// **'remind your partner about a plan that\'s stalled'**
  String get sincerityExplainNudgePartner;

  /// No description provided for @sincerityNoPointsForVolume.
  ///
  /// In en, this message translates to:
  /// **'there are no points for how many entries, ratings, or notes you write — only for honest choices. but what you\'ve collected isn\'t just a number: you can really spend it, right on this screen and in the shared diary.'**
  String get sincerityNoPointsForVolume;

  /// No description provided for @sincerityPayOffDebtTitle.
  ///
  /// In en, this message translates to:
  /// **'pay off the debt?'**
  String get sincerityPayOffDebtTitle;

  /// No description provided for @sincerityPayOffDebtBody.
  ///
  /// In en, this message translates to:
  /// **'has been sitting in your plans untouched for too long. pay once — and it will never drain your points again.'**
  String get sincerityPayOffDebtBody;

  /// No description provided for @sincerityPayOffConfirm.
  ///
  /// In en, this message translates to:
  /// **'pay off'**
  String get sincerityPayOffConfirm;

  /// No description provided for @sincerityDebtBuildingUp.
  ///
  /// In en, this message translates to:
  /// **'debt is building up'**
  String get sincerityDebtBuildingUp;

  /// No description provided for @sincerityDebtBuildingUpHint.
  ///
  /// In en, this message translates to:
  /// **'these titles have sat in your plans untouched for too long — pay them off once and forget about it'**
  String get sincerityDebtBuildingUpHint;

  /// No description provided for @sincerityInPlansFor.
  ///
  /// In en, this message translates to:
  /// **'in your plans for'**
  String get sincerityInPlansFor;

  /// No description provided for @sincerityStakesInPlay.
  ///
  /// In en, this message translates to:
  /// **'stakes in play'**
  String get sincerityStakesInPlay;

  /// No description provided for @sincerityStakeSettlesItself.
  ///
  /// In en, this message translates to:
  /// **'settles on its own once your friend rates the title'**
  String get sincerityStakeSettlesItself;

  /// No description provided for @sincerityYouStakedOn.
  ///
  /// In en, this message translates to:
  /// **'you staked on'**
  String get sincerityYouStakedOn;

  /// No description provided for @sincerityStakedOnYou.
  ///
  /// In en, this message translates to:
  /// **'staked on you'**
  String get sincerityStakedOnYou;

  /// No description provided for @sincerityHistorySecondChance.
  ///
  /// In en, this message translates to:
  /// **'gave it a second chance — and finished it'**
  String get sincerityHistorySecondChance;

  /// No description provided for @sincerityHistoryRatedOwn.
  ///
  /// In en, this message translates to:
  /// **'rated it yourself, no peeking'**
  String get sincerityHistoryRatedOwn;

  /// No description provided for @sincerityHistoryStakeReturned.
  ///
  /// In en, this message translates to:
  /// **'stake didn\'t play out — returned'**
  String get sincerityHistoryStakeReturned;

  /// No description provided for @sincerityHistoryPeekedEarly.
  ///
  /// In en, this message translates to:
  /// **'opened your partner\'s rating early'**
  String get sincerityHistoryPeekedEarly;

  /// No description provided for @sincerityHistoryDebtPaidForGood.
  ///
  /// In en, this message translates to:
  /// **'paid off the debt for good'**
  String get sincerityHistoryDebtPaidForGood;

  /// No description provided for @sincerityHistoryBoughtSlot.
  ///
  /// In en, this message translates to:
  /// **'bought a slot in the awards showcase'**
  String get sincerityHistoryBoughtSlot;

  /// No description provided for @sincerityHistoryNudgedPlan.
  ///
  /// In en, this message translates to:
  /// **'reminded about a shared plan'**
  String get sincerityHistoryNudgedPlan;

  /// No description provided for @recommendStakePlacedLead.
  ///
  /// In en, this message translates to:
  /// **'stake placed —'**
  String get recommendStakePlacedLead;

  /// No description provided for @recommendStakePlacedTail.
  ///
  /// In en, this message translates to:
  /// **'will find out when they rate the title'**
  String get recommendStakePlacedTail;

  /// No description provided for @recommendStakeTitle.
  ///
  /// In en, this message translates to:
  /// **'stake on a recommendation'**
  String get recommendStakeTitle;

  /// No description provided for @recommendStakeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'predict how your friend will rate it, and stake points on being right'**
  String get recommendStakeSubtitle;

  /// No description provided for @recommendTo.
  ///
  /// In en, this message translates to:
  /// **'recommend to'**
  String get recommendTo;

  /// No description provided for @recommendNoFriendsYet.
  ///
  /// In en, this message translates to:
  /// **'no one to stake with yet — add friends to place stakes'**
  String get recommendNoFriendsYet;

  /// No description provided for @recommendPredictedRating.
  ///
  /// In en, this message translates to:
  /// **'predicted rating'**
  String get recommendPredictedRating;

  /// No description provided for @recommendYourStake.
  ///
  /// In en, this message translates to:
  /// **'your stake'**
  String get recommendYourStake;

  /// No description provided for @recommendPlaceStake.
  ///
  /// In en, this message translates to:
  /// **'stake'**
  String get recommendPlaceStake;

  /// No description provided for @spendConfirmDefault.
  ///
  /// In en, this message translates to:
  /// **'spend'**
  String get spendConfirmDefault;

  /// No description provided for @spendNotEnoughSincerity.
  ///
  /// In en, this message translates to:
  /// **'not enough sincerity points'**
  String get spendNotEnoughSincerity;

  /// No description provided for @homeRandomReelOrSwipe.
  ///
  /// In en, this message translates to:
  /// **'random, reel or swipe'**
  String get homeRandomReelOrSwipe;

  /// No description provided for @skinClayLabel.
  ///
  /// In en, this message translates to:
  /// **'clay'**
  String get skinClayLabel;

  /// No description provided for @skinClaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'puffy pastel'**
  String get skinClaySubtitle;

  /// No description provided for @skinLightOrangeStrawberryNote.
  ///
  /// In en, this message translates to:
  /// **'orange and strawberry are always light — that\'s the whole point, not a bug'**
  String get skinLightOrangeStrawberryNote;

  /// No description provided for @profileChallengesTitle.
  ///
  /// In en, this message translates to:
  /// **'challenges'**
  String get profileChallengesTitle;

  /// No description provided for @challengesCouldntLoad.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load challenges right now'**
  String get challengesCouldntLoad;

  /// No description provided for @challengesNewOnTheWay.
  ///
  /// In en, this message translates to:
  /// **'new challenges are on their way'**
  String get challengesNewOnTheWay;

  /// No description provided for @challengeCollect.
  ///
  /// In en, this message translates to:
  /// **'collect'**
  String get challengeCollect;

  /// Wrapped-teaser stat label ('hrs'). Its Russian text equals an older key's ('ч'), which is used as a Russian source in stats_screen.dart. Keep this key's name sorting BEFORE that key ('h') — generate_compat_layer.py sorts keys and the last one wins the reverse (ru->en) lookup, so the older wording stays.
  ///
  /// In en, this message translates to:
  /// **'hrs'**
  String get compactHoursLabel;

  /// Wrapped-teaser stat label ('streak'). Its Russian text equals an older key's ('серия'), which is used as a Russian source in stats_screen.dart. Keep this key's name sorting BEFORE that key ('episode') — generate_compat_layer.py sorts keys and the last one wins the reverse (ru->en) lookup, so the older wording stays.
  ///
  /// In en, this message translates to:
  /// **'streak'**
  String get compactStreakLabel;

  /// No description provided for @wrappedTeaserNothingYet.
  ///
  /// In en, this message translates to:
  /// **'nothing logged yet this month'**
  String get wrappedTeaserNothingYet;

  /// No description provided for @reviewsProvidedBySteam.
  ///
  /// In en, this message translates to:
  /// **'Reviews provided by Steam'**
  String get reviewsProvidedBySteam;

  /// No description provided for @reviewsProvidedByAniList.
  ///
  /// In en, this message translates to:
  /// **'Reviews provided by AniList'**
  String get reviewsProvidedByAniList;

  /// No description provided for @toneRecommends.
  ///
  /// In en, this message translates to:
  /// **'recommends'**
  String get toneRecommends;

  /// No description provided for @toneDoesNotRecommend.
  ///
  /// In en, this message translates to:
  /// **'doesn\'t recommend'**
  String get toneDoesNotRecommend;

  /// No description provided for @playtimeHoursInGame.
  ///
  /// In en, this message translates to:
  /// **'h in game'**
  String get playtimeHoursInGame;

  /// No description provided for @ratingSteamPositive.
  ///
  /// In en, this message translates to:
  /// **'steam · positive'**
  String get ratingSteamPositive;

  /// No description provided for @extrasMetacritic.
  ///
  /// In en, this message translates to:
  /// **'Metacritic'**
  String get extrasMetacritic;

  /// No description provided for @extrasAboutTheAuthorFromOpenLibrary.
  ///
  /// In en, this message translates to:
  /// **'about the author from Open Library'**
  String get extrasAboutTheAuthorFromOpenLibrary;

  /// No description provided for @extrasAchievements.
  ///
  /// In en, this message translates to:
  /// **'achievements'**
  String get extrasAchievements;

  /// No description provided for @extrasAlsoKnownAs.
  ///
  /// In en, this message translates to:
  /// **'also known as'**
  String get extrasAlsoKnownAs;

  /// No description provided for @extrasAuthor.
  ///
  /// In en, this message translates to:
  /// **'author'**
  String get extrasAuthor;

  /// No description provided for @extrasAuthors.
  ///
  /// In en, this message translates to:
  /// **'authors'**
  String get extrasAuthors;

  /// No description provided for @extrasCharacters.
  ///
  /// In en, this message translates to:
  /// **'characters'**
  String get extrasCharacters;

  /// No description provided for @extrasCompletionist.
  ///
  /// In en, this message translates to:
  /// **'completionist'**
  String get extrasCompletionist;

  /// No description provided for @extrasConnectedWorks.
  ///
  /// In en, this message translates to:
  /// **'connected works'**
  String get extrasConnectedWorks;

  /// No description provided for @extrasCouldnTFindThatTitle.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t find that title'**
  String get extrasCouldnTFindThatTitle;

  /// No description provided for @extrasCreators.
  ///
  /// In en, this message translates to:
  /// **'creators'**
  String get extrasCreators;

  /// No description provided for @extrasCritics.
  ///
  /// In en, this message translates to:
  /// **'critics'**
  String get extrasCritics;

  /// No description provided for @extrasEpisodes.
  ///
  /// In en, this message translates to:
  /// **'episodes'**
  String get extrasEpisodes;

  /// No description provided for @extrasFirstLine.
  ///
  /// In en, this message translates to:
  /// **'first line'**
  String get extrasFirstLine;

  /// No description provided for @extrasFreeToPlay.
  ///
  /// In en, this message translates to:
  /// **'free to play'**
  String get extrasFreeToPlay;

  /// No description provided for @extrasHaveRead.
  ///
  /// In en, this message translates to:
  /// **'have read'**
  String get extrasHaveRead;

  /// No description provided for @extrasInterface.
  ///
  /// In en, this message translates to:
  /// **'interface'**
  String get extrasInterface;

  /// No description provided for @extrasLanguages.
  ///
  /// In en, this message translates to:
  /// **'languages'**
  String get extrasLanguages;

  /// No description provided for @extrasMoreFromThisAuthor.
  ///
  /// In en, this message translates to:
  /// **'more from this author'**
  String get extrasMoreFromThisAuthor;

  /// No description provided for @extrasNextEpisode.
  ///
  /// In en, this message translates to:
  /// **'next episode'**
  String get extrasNextEpisode;

  /// No description provided for @extrasNoRussianVersion.
  ///
  /// In en, this message translates to:
  /// **'no Russian version'**
  String get extrasNoRussianVersion;

  /// No description provided for @extrasOngoing.
  ///
  /// In en, this message translates to:
  /// **'ongoing'**
  String get extrasOngoing;

  /// No description provided for @extrasPages.
  ///
  /// In en, this message translates to:
  /// **'pages'**
  String get extrasPages;

  /// No description provided for @extrasPlayers.
  ///
  /// In en, this message translates to:
  /// **'players'**
  String get extrasPlayers;

  /// No description provided for @extrasReadMore.
  ///
  /// In en, this message translates to:
  /// **'read more'**
  String get extrasReadMore;

  /// No description provided for @extrasReadOrBuy.
  ///
  /// In en, this message translates to:
  /// **'read or buy'**
  String get extrasReadOrBuy;

  /// No description provided for @extrasReaderCountsFromOpenLibrary.
  ///
  /// In en, this message translates to:
  /// **'reader counts from Open Library'**
  String get extrasReaderCountsFromOpenLibrary;

  /// No description provided for @extrasReaders.
  ///
  /// In en, this message translates to:
  /// **'readers'**
  String get extrasReaders;

  /// No description provided for @extrasReading.
  ///
  /// In en, this message translates to:
  /// **'reading'**
  String get extrasReading;

  /// No description provided for @extrasScreenshots.
  ///
  /// In en, this message translates to:
  /// **'screenshots'**
  String get extrasScreenshots;

  /// No description provided for @extrasShowLess.
  ///
  /// In en, this message translates to:
  /// **'show less'**
  String get extrasShowLess;

  /// No description provided for @extrasStory.
  ///
  /// In en, this message translates to:
  /// **'story'**
  String get extrasStory;

  /// No description provided for @extrasStoryPlusExtras.
  ///
  /// In en, this message translates to:
  /// **'story + extras'**
  String get extrasStoryPlusExtras;

  /// No description provided for @extrasStoryline.
  ///
  /// In en, this message translates to:
  /// **'storyline'**
  String get extrasStoryline;

  /// No description provided for @extrasSubtitles.
  ///
  /// In en, this message translates to:
  /// **'subtitles'**
  String get extrasSubtitles;

  /// No description provided for @extrasThemes.
  ///
  /// In en, this message translates to:
  /// **'themes'**
  String get extrasThemes;

  /// No description provided for @extrasTimeToBeat.
  ///
  /// In en, this message translates to:
  /// **'time to beat'**
  String get extrasTimeToBeat;

  /// No description provided for @extrasToRead.
  ///
  /// In en, this message translates to:
  /// **'to read'**
  String get extrasToRead;

  /// No description provided for @extrasVoiceOver.
  ///
  /// In en, this message translates to:
  /// **'voice-over'**
  String get extrasVoiceOver;

  /// No description provided for @extrasWantToRead.
  ///
  /// In en, this message translates to:
  /// **'want to read'**
  String get extrasWantToRead;

  /// No description provided for @extrasWhereToPlay.
  ///
  /// In en, this message translates to:
  /// **'where to play'**
  String get extrasWhereToPlay;

  /// No description provided for @extrasWhereToRead.
  ///
  /// In en, this message translates to:
  /// **'where to read'**
  String get extrasWhereToRead;

  /// No description provided for @extrasBasedOn.
  ///
  /// In en, this message translates to:
  /// **'based on'**
  String get extrasBasedOn;

  /// No description provided for @extrasInLists.
  ///
  /// In en, this message translates to:
  /// **'in lists'**
  String get extrasInLists;

  /// No description provided for @extrasRussian.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get extrasRussian;

  /// No description provided for @extrasEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get extrasEnglish;

  /// No description provided for @extrasGerman.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get extrasGerman;

  /// No description provided for @extrasFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get extrasFrench;

  /// No description provided for @extrasSpanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get extrasSpanish;

  /// No description provided for @extrasItalian.
  ///
  /// In en, this message translates to:
  /// **'Italian'**
  String get extrasItalian;

  /// No description provided for @extrasPortuguese.
  ///
  /// In en, this message translates to:
  /// **'Portuguese'**
  String get extrasPortuguese;

  /// No description provided for @extrasJapanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get extrasJapanese;

  /// No description provided for @extrasKorean.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get extrasKorean;

  /// No description provided for @extrasChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get extrasChinese;

  /// No description provided for @extrasPolish.
  ///
  /// In en, this message translates to:
  /// **'Polish'**
  String get extrasPolish;

  /// No description provided for @extrasTurkish.
  ///
  /// In en, this message translates to:
  /// **'Turkish'**
  String get extrasTurkish;

  /// No description provided for @extrasUkrainian.
  ///
  /// In en, this message translates to:
  /// **'Ukrainian'**
  String get extrasUkrainian;

  /// No description provided for @extrasCzech.
  ///
  /// In en, this message translates to:
  /// **'Czech'**
  String get extrasCzech;

  /// No description provided for @extrasDutch.
  ///
  /// In en, this message translates to:
  /// **'Dutch'**
  String get extrasDutch;

  /// No description provided for @extrasArabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get extrasArabic;

  /// No description provided for @extrasSwedish.
  ///
  /// In en, this message translates to:
  /// **'Swedish'**
  String get extrasSwedish;

  /// No description provided for @extrasFinnish.
  ///
  /// In en, this message translates to:
  /// **'Finnish'**
  String get extrasFinnish;

  /// No description provided for @extrasNorwegian.
  ///
  /// In en, this message translates to:
  /// **'Norwegian'**
  String get extrasNorwegian;

  /// No description provided for @extrasDanish.
  ///
  /// In en, this message translates to:
  /// **'Danish'**
  String get extrasDanish;

  /// No description provided for @extrasHungarian.
  ///
  /// In en, this message translates to:
  /// **'Hungarian'**
  String get extrasHungarian;

  /// No description provided for @extrasRomanian.
  ///
  /// In en, this message translates to:
  /// **'Romanian'**
  String get extrasRomanian;

  /// No description provided for @extrasThai.
  ///
  /// In en, this message translates to:
  /// **'Thai'**
  String get extrasThai;

  /// No description provided for @extrasHebrew.
  ///
  /// In en, this message translates to:
  /// **'Hebrew'**
  String get extrasHebrew;

  /// No description provided for @extrasGreek.
  ///
  /// In en, this message translates to:
  /// **'Greek'**
  String get extrasGreek;

  /// No description provided for @extrasBulgarian.
  ///
  /// In en, this message translates to:
  /// **'Bulgarian'**
  String get extrasBulgarian;

  /// No description provided for @extrasVietnamese.
  ///
  /// In en, this message translates to:
  /// **'Vietnamese'**
  String get extrasVietnamese;

  /// No description provided for @extrasHindi.
  ///
  /// In en, this message translates to:
  /// **'Hindi'**
  String get extrasHindi;

  /// No description provided for @extrasIndonesian.
  ///
  /// In en, this message translates to:
  /// **'Indonesian'**
  String get extrasIndonesian;

  /// No description provided for @extrasSimplifiedChinese.
  ///
  /// In en, this message translates to:
  /// **'Simplified Chinese'**
  String get extrasSimplifiedChinese;

  /// No description provided for @extrasTraditionalChinese.
  ///
  /// In en, this message translates to:
  /// **'Traditional Chinese'**
  String get extrasTraditionalChinese;

  /// No description provided for @extrasAuthor2.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get extrasAuthor2;

  /// No description provided for @extrasStory2.
  ///
  /// In en, this message translates to:
  /// **'Story'**
  String get extrasStory2;

  /// No description provided for @extrasArt.
  ///
  /// In en, this message translates to:
  /// **'Art'**
  String get extrasArt;

  /// No description provided for @extrasStoryAndArt.
  ///
  /// In en, this message translates to:
  /// **'Story & Art'**
  String get extrasStoryAndArt;

  /// No description provided for @extrasDirector.
  ///
  /// In en, this message translates to:
  /// **'Director'**
  String get extrasDirector;

  /// No description provided for @extrasOriginalCreator.
  ///
  /// In en, this message translates to:
  /// **'Original Creator'**
  String get extrasOriginalCreator;

  /// No description provided for @extrasSeriesComposition.
  ///
  /// In en, this message translates to:
  /// **'Series Composition'**
  String get extrasSeriesComposition;

  /// No description provided for @extrasScript.
  ///
  /// In en, this message translates to:
  /// **'Script'**
  String get extrasScript;

  /// No description provided for @extrasCharacterDesign.
  ///
  /// In en, this message translates to:
  /// **'Character Design'**
  String get extrasCharacterDesign;

  /// No description provided for @extrasMusic.
  ///
  /// In en, this message translates to:
  /// **'Music'**
  String get extrasMusic;

  /// No description provided for @extrasMain.
  ///
  /// In en, this message translates to:
  /// **'Main'**
  String get extrasMain;

  /// No description provided for @extrasSupporting.
  ///
  /// In en, this message translates to:
  /// **'Supporting'**
  String get extrasSupporting;

  /// No description provided for @extrasOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get extrasOriginal;

  /// No description provided for @extrasManga.
  ///
  /// In en, this message translates to:
  /// **'Manga'**
  String get extrasManga;

  /// No description provided for @extrasLightNovel.
  ///
  /// In en, this message translates to:
  /// **'Light novel'**
  String get extrasLightNovel;

  /// No description provided for @extrasNovel.
  ///
  /// In en, this message translates to:
  /// **'Novel'**
  String get extrasNovel;

  /// No description provided for @extrasWebNovel.
  ///
  /// In en, this message translates to:
  /// **'Web novel'**
  String get extrasWebNovel;

  /// No description provided for @extrasVisualNovel.
  ///
  /// In en, this message translates to:
  /// **'Visual novel'**
  String get extrasVisualNovel;

  /// No description provided for @extrasVideoGame.
  ///
  /// In en, this message translates to:
  /// **'Video game'**
  String get extrasVideoGame;

  /// No description provided for @extrasDoujinshi.
  ///
  /// In en, this message translates to:
  /// **'Doujinshi'**
  String get extrasDoujinshi;

  /// No description provided for @extrasComic.
  ///
  /// In en, this message translates to:
  /// **'Comic'**
  String get extrasComic;

  /// No description provided for @extrasLiveAction.
  ///
  /// In en, this message translates to:
  /// **'Live action'**
  String get extrasLiveAction;

  /// No description provided for @extrasAnime.
  ///
  /// In en, this message translates to:
  /// **'Anime'**
  String get extrasAnime;

  /// No description provided for @extrasAdaptation.
  ///
  /// In en, this message translates to:
  /// **'Adaptation'**
  String get extrasAdaptation;

  /// No description provided for @extrasPrequel.
  ///
  /// In en, this message translates to:
  /// **'Prequel'**
  String get extrasPrequel;

  /// No description provided for @extrasSequel.
  ///
  /// In en, this message translates to:
  /// **'Sequel'**
  String get extrasSequel;

  /// No description provided for @extrasParentStory.
  ///
  /// In en, this message translates to:
  /// **'Parent Story'**
  String get extrasParentStory;

  /// No description provided for @extrasSideStory.
  ///
  /// In en, this message translates to:
  /// **'Side Story'**
  String get extrasSideStory;

  /// No description provided for @extrasSpinOff.
  ///
  /// In en, this message translates to:
  /// **'Spin-off'**
  String get extrasSpinOff;

  /// No description provided for @extrasAlternativeVersion.
  ///
  /// In en, this message translates to:
  /// **'Alternative Version'**
  String get extrasAlternativeVersion;

  /// No description provided for @extrasAlternativeSetting.
  ///
  /// In en, this message translates to:
  /// **'Alternative Setting'**
  String get extrasAlternativeSetting;

  /// No description provided for @extrasSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get extrasSummary;

  /// No description provided for @extrasBaseGame.
  ///
  /// In en, this message translates to:
  /// **'Base game'**
  String get extrasBaseGame;

  /// No description provided for @extrasSameSeries.
  ///
  /// In en, this message translates to:
  /// **'Same series'**
  String get extrasSameSeries;

  /// No description provided for @extrasDLC.
  ///
  /// In en, this message translates to:
  /// **'DLC'**
  String get extrasDLC;

  /// No description provided for @extrasExpansion.
  ///
  /// In en, this message translates to:
  /// **'Expansion'**
  String get extrasExpansion;

  /// No description provided for @extrasRemake.
  ///
  /// In en, this message translates to:
  /// **'Remake'**
  String get extrasRemake;

  /// No description provided for @extrasRemaster.
  ///
  /// In en, this message translates to:
  /// **'Remaster'**
  String get extrasRemaster;

  /// No description provided for @extrasOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get extrasOther;

  /// No description provided for @extrasCharacter.
  ///
  /// In en, this message translates to:
  /// **'Character'**
  String get extrasCharacter;

  /// No description provided for @extrasOfficialSite.
  ///
  /// In en, this message translates to:
  /// **'Official site'**
  String get extrasOfficialSite;

  /// No description provided for @extrasWikipedia.
  ///
  /// In en, this message translates to:
  /// **'Wikipedia'**
  String get extrasWikipedia;

  /// No description provided for @extrasReadASample.
  ///
  /// In en, this message translates to:
  /// **'Read a sample'**
  String get extrasReadASample;

  /// No description provided for @extrasFullControllerSupport.
  ///
  /// In en, this message translates to:
  /// **'Full controller support'**
  String get extrasFullControllerSupport;

  /// No description provided for @extrasPartialControllerSupport.
  ///
  /// In en, this message translates to:
  /// **'Partial controller support'**
  String get extrasPartialControllerSupport;

  /// No description provided for @extrasSteamCloud.
  ///
  /// In en, this message translates to:
  /// **'Steam Cloud'**
  String get extrasSteamCloud;

  /// No description provided for @extrasFirstPerson.
  ///
  /// In en, this message translates to:
  /// **'First person'**
  String get extrasFirstPerson;

  /// No description provided for @extrasThirdPerson.
  ///
  /// In en, this message translates to:
  /// **'Third person'**
  String get extrasThirdPerson;

  /// No description provided for @extrasBirdViewIsometric.
  ///
  /// In en, this message translates to:
  /// **'Bird view / Isometric'**
  String get extrasBirdViewIsometric;

  /// No description provided for @extrasSideView.
  ///
  /// In en, this message translates to:
  /// **'Side view'**
  String get extrasSideView;

  /// No description provided for @extrasText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get extrasText;

  /// No description provided for @extrasAuditory.
  ///
  /// In en, this message translates to:
  /// **'Auditory'**
  String get extrasAuditory;

  /// No description provided for @extrasVirtualReality.
  ///
  /// In en, this message translates to:
  /// **'Virtual Reality'**
  String get extrasVirtualReality;

  /// No description provided for @extrasFantasy.
  ///
  /// In en, this message translates to:
  /// **'Fantasy'**
  String get extrasFantasy;

  /// No description provided for @extrasScienceFiction.
  ///
  /// In en, this message translates to:
  /// **'Science fiction'**
  String get extrasScienceFiction;

  /// No description provided for @extrasHorror.
  ///
  /// In en, this message translates to:
  /// **'Horror'**
  String get extrasHorror;

  /// No description provided for @extrasThriller.
  ///
  /// In en, this message translates to:
  /// **'Thriller'**
  String get extrasThriller;

  /// No description provided for @extrasSurvival.
  ///
  /// In en, this message translates to:
  /// **'Survival'**
  String get extrasSurvival;

  /// No description provided for @extrasHistorical.
  ///
  /// In en, this message translates to:
  /// **'Historical'**
  String get extrasHistorical;

  /// No description provided for @extrasStealth.
  ///
  /// In en, this message translates to:
  /// **'Stealth'**
  String get extrasStealth;

  /// No description provided for @extrasComedy.
  ///
  /// In en, this message translates to:
  /// **'Comedy'**
  String get extrasComedy;

  /// No description provided for @extrasBusiness.
  ///
  /// In en, this message translates to:
  /// **'Business'**
  String get extrasBusiness;

  /// No description provided for @extrasDrama.
  ///
  /// In en, this message translates to:
  /// **'Drama'**
  String get extrasDrama;

  /// No description provided for @extrasNonFiction.
  ///
  /// In en, this message translates to:
  /// **'Non-fiction'**
  String get extrasNonFiction;

  /// No description provided for @extrasSandbox.
  ///
  /// In en, this message translates to:
  /// **'Sandbox'**
  String get extrasSandbox;

  /// No description provided for @extrasEducational.
  ///
  /// In en, this message translates to:
  /// **'Educational'**
  String get extrasEducational;

  /// No description provided for @extrasKids.
  ///
  /// In en, this message translates to:
  /// **'Kids'**
  String get extrasKids;

  /// No description provided for @extrasOpenWorld.
  ///
  /// In en, this message translates to:
  /// **'Open world'**
  String get extrasOpenWorld;

  /// No description provided for @extrasWarfare.
  ///
  /// In en, this message translates to:
  /// **'Warfare'**
  String get extrasWarfare;

  /// No description provided for @extrasParty.
  ///
  /// In en, this message translates to:
  /// **'Party'**
  String get extrasParty;

  /// No description provided for @extras4X.
  ///
  /// In en, this message translates to:
  /// **'4X'**
  String get extras4X;

  /// No description provided for @extrasMystery.
  ///
  /// In en, this message translates to:
  /// **'Mystery'**
  String get extrasMystery;

  /// No description provided for @extrasRomance.
  ///
  /// In en, this message translates to:
  /// **'Romance'**
  String get extrasRomance;

  /// No description provided for @extrasAction.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get extrasAction;

  /// No description provided for @extrasSteamDeckVerified.
  ///
  /// In en, this message translates to:
  /// **'Steam Deck verified'**
  String get extrasSteamDeckVerified;

  /// No description provided for @extrasSteamDeckPlayable.
  ///
  /// In en, this message translates to:
  /// **'Steam Deck playable'**
  String get extrasSteamDeckPlayable;

  /// No description provided for @extrasSteamDeckUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Steam Deck unsupported'**
  String get extrasSteamDeckUnsupported;

  /// No description provided for @extrasSteamDeckVerifiedPlaysGreatOutOfTheBox.
  ///
  /// In en, this message translates to:
  /// **'Steam Deck verified — plays great out of the box'**
  String get extrasSteamDeckVerifiedPlaysGreatOutOfTheBox;

  /// No description provided for @extrasSteamDeckPlayableMayNeedAFewTweaks.
  ///
  /// In en, this message translates to:
  /// **'Steam Deck playable — may need a few tweaks'**
  String get extrasSteamDeckPlayableMayNeedAFewTweaks;

  /// No description provided for @extrasSteamDeckUnsupportedValveSaysItWonTRunWell.
  ///
  /// In en, this message translates to:
  /// **'Steam Deck unsupported — Valve says it won\'t run well'**
  String get extrasSteamDeckUnsupportedValveSaysItWonTRunWell;

  /// No description provided for @extrasChapter.
  ///
  /// In en, this message translates to:
  /// **'chapter'**
  String get extrasChapter;

  /// No description provided for @extrasChapterYouAreOn.
  ///
  /// In en, this message translates to:
  /// **'chapter you are on'**
  String get extrasChapterYouAreOn;

  /// No description provided for @extrasCouldnTSaveProgressJustNow.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t save progress just now'**
  String get extrasCouldnTSaveProgressJustNow;

  /// No description provided for @extrasLogItInYourDiary.
  ///
  /// In en, this message translates to:
  /// **'log it in your diary'**
  String get extrasLogItInYourDiary;

  /// No description provided for @extrasMinimum.
  ///
  /// In en, this message translates to:
  /// **'minimum'**
  String get extrasMinimum;

  /// No description provided for @extrasRecommended.
  ///
  /// In en, this message translates to:
  /// **'recommended'**
  String get extrasRecommended;

  /// No description provided for @extrasPage.
  ///
  /// In en, this message translates to:
  /// **'page'**
  String get extrasPage;

  /// No description provided for @extrasPageYouAreOn.
  ///
  /// In en, this message translates to:
  /// **'page you are on'**
  String get extrasPageYouAreOn;

  /// No description provided for @extrasProgressCleared.
  ///
  /// In en, this message translates to:
  /// **'progress cleared'**
  String get extrasProgressCleared;

  /// No description provided for @extrasReadingProgress.
  ///
  /// In en, this message translates to:
  /// **'reading progress'**
  String get extrasReadingProgress;

  /// No description provided for @extrasStartOver.
  ///
  /// In en, this message translates to:
  /// **'start over'**
  String get extrasStartOver;

  /// No description provided for @extrasSystemRequirements.
  ///
  /// In en, this message translates to:
  /// **'system requirements'**
  String get extrasSystemRequirements;

  /// No description provided for @extrasTapToSet.
  ///
  /// In en, this message translates to:
  /// **'tap to set'**
  String get extrasTapToSet;

  /// No description provided for @extrasToGo.
  ///
  /// In en, this message translates to:
  /// **'to go'**
  String get extrasToGo;

  /// No description provided for @extrasUndo.
  ///
  /// In en, this message translates to:
  /// **'undo'**
  String get extrasUndo;

  /// No description provided for @extrasVolume.
  ///
  /// In en, this message translates to:
  /// **'volume'**
  String get extrasVolume;

  /// No description provided for @extrasVolumeYouAreOn.
  ///
  /// In en, this message translates to:
  /// **'volume you are on'**
  String get extrasVolumeYouAreOn;

  /// No description provided for @extrasYouReachedTheEnd.
  ///
  /// In en, this message translates to:
  /// **'you reached the end'**
  String get extrasYouReachedTheEnd;

  /// No description provided for @extrasOS.
  ///
  /// In en, this message translates to:
  /// **'OS'**
  String get extrasOS;

  /// No description provided for @extrasProcessor.
  ///
  /// In en, this message translates to:
  /// **'Processor'**
  String get extrasProcessor;

  /// No description provided for @extrasMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get extrasMemory;

  /// No description provided for @extrasGraphics.
  ///
  /// In en, this message translates to:
  /// **'Graphics'**
  String get extrasGraphics;

  /// No description provided for @extrasDirectX.
  ///
  /// In en, this message translates to:
  /// **'DirectX'**
  String get extrasDirectX;

  /// No description provided for @extrasStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get extrasStorage;

  /// No description provided for @extrasSoundCard.
  ///
  /// In en, this message translates to:
  /// **'Sound card'**
  String get extrasSoundCard;

  /// No description provided for @extrasNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get extrasNetwork;

  /// No description provided for @extrasAdditionalNotes.
  ///
  /// In en, this message translates to:
  /// **'Additional notes'**
  String get extrasAdditionalNotes;

  /// Plural: volume / volumes — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} volume} other {{count} volumes}}'**
  String nVolumes(int count);

  /// Plural: chapter / chapters — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} chapter} other {{count} chapters}}'**
  String nChapters(int count);

  /// Plural: page / pages — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} page} other {{count} pages}}'**
  String nPages(int count);

  /// No description provided for @coViewLoggedItButCouldnTRemove.
  ///
  /// In en, this message translates to:
  /// **'logged it, but couldn\'t remove it from \"planned\" — try again'**
  String get coViewLoggedItButCouldnTRemove;

  /// No description provided for @coViewABiggerCircleIsPremium.
  ///
  /// In en, this message translates to:
  /// **'a bigger circle needs premium'**
  String get coViewABiggerCircleIsPremium;

  /// No description provided for @coViewAPairIsAlwaysFreeWith.
  ///
  /// In en, this message translates to:
  /// **'a pair is always free — with premium you can watch together as a group, three or more'**
  String get coViewAPairIsAlwaysFreeWith;

  /// No description provided for @coViewThisEndsCoViewingBetweenYou.
  ///
  /// In en, this message translates to:
  /// **'this ends co-viewing between you two — what\'s already in each of your diaries stays where it is.'**
  String get coViewThisEndsCoViewingBetweenYou;

  /// No description provided for @coViewCouldnTEndTheLinkTry.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t end the link — try again'**
  String get coViewCouldnTEndTheLinkTry;

  /// No description provided for @coViewUs.
  ///
  /// In en, this message translates to:
  /// **'us'**
  String get coViewUs;

  /// No description provided for @coViewNothingHereYetAddSomethingWith.
  ///
  /// In en, this message translates to:
  /// **'nothing here yet — add something with the heart on a movie\'s page'**
  String get coViewNothingHereYetAddSomethingWith;

  /// No description provided for @coViewYourSharedEveningsWillLiveHere.
  ///
  /// In en, this message translates to:
  /// **'your shared evenings will live here'**
  String get coViewYourSharedEveningsWillLiveHere;

  /// No description provided for @coViewMarkSomethingAsWatchedTogetherOr.
  ///
  /// In en, this message translates to:
  /// **'mark something as watched together — or turn on \"log my evenings to the shared diary\" in settings'**
  String get coViewMarkSomethingAsWatchedTogetherOr;

  /// No description provided for @coViewShowMore.
  ///
  /// In en, this message translates to:
  /// **'show more'**
  String get coViewShowMore;

  /// No description provided for @coViewStatsWillAppearAfterYourFirst.
  ///
  /// In en, this message translates to:
  /// **'stats will appear after your first shared evening'**
  String get coViewStatsWillAppearAfterYourFirst;

  /// No description provided for @coViewWatchingTogether.
  ///
  /// In en, this message translates to:
  /// **'watching together'**
  String get coViewWatchingTogether;

  /// No description provided for @coViewCanTChoose.
  ///
  /// In en, this message translates to:
  /// **'can\'t choose'**
  String get coViewCanTChoose;

  /// No description provided for @coViewAVoteARouletteOrAsk.
  ///
  /// In en, this message translates to:
  /// **'a vote, a roulette, or ask tanè'**
  String get coViewAVoteARouletteOrAsk;

  /// No description provided for @coViewUnlimited.
  ///
  /// In en, this message translates to:
  /// **'unlimited'**
  String get coViewUnlimited;

  /// No description provided for @coViewWatchedTogether.
  ///
  /// In en, this message translates to:
  /// **'watched together'**
  String get coViewWatchedTogether;

  /// No description provided for @coViewWatchedAlone.
  ///
  /// In en, this message translates to:
  /// **'watched alone'**
  String get coViewWatchedAlone;

  /// No description provided for @coViewYou.
  ///
  /// In en, this message translates to:
  /// **'you'**
  String get coViewYou;

  /// No description provided for @coViewHoursSideBySide.
  ///
  /// In en, this message translates to:
  /// **'hours side by side'**
  String get coViewHoursSideBySide;

  /// No description provided for @coViewSharedEntries.
  ///
  /// In en, this message translates to:
  /// **'shared entries'**
  String get coViewSharedEntries;

  /// No description provided for @coViewWhoRatesMoreGenerously.
  ///
  /// In en, this message translates to:
  /// **'who rates more generously'**
  String get coViewWhoRatesMoreGenerously;

  /// No description provided for @coViewWhoSuggestsMoreOften.
  ///
  /// In en, this message translates to:
  /// **'who suggests more often'**
  String get coViewWhoSuggestsMoreOften;

  /// No description provided for @coViewYourGenres.
  ///
  /// In en, this message translates to:
  /// **'your genres'**
  String get coViewYourGenres;

  /// No description provided for @coViewSharedLove.
  ///
  /// In en, this message translates to:
  /// **'shared love'**
  String get coViewSharedLove;

  /// No description provided for @coViewYouBothLikedIt.
  ///
  /// In en, this message translates to:
  /// **'you both liked it'**
  String get coViewYouBothLikedIt;

  /// No description provided for @coViewWhereYouDidnTAgree.
  ///
  /// In en, this message translates to:
  /// **'where you didn\'t agree'**
  String get coViewWhereYouDidnTAgree;

  /// No description provided for @coViewYou2.
  ///
  /// In en, this message translates to:
  /// **'you'**
  String get coViewYou2;

  /// No description provided for @coViewOurMilestones.
  ///
  /// In en, this message translates to:
  /// **'our milestones'**
  String get coViewOurMilestones;

  /// No description provided for @coViewOurWrapped.
  ///
  /// In en, this message translates to:
  /// **'our wrapped'**
  String get coViewOurWrapped;

  /// No description provided for @coViewYourMovieEveningsJustTheTwo.
  ///
  /// In en, this message translates to:
  /// **'your movie evenings, just the two of you'**
  String get coViewYourMovieEveningsJustTheTwo;

  /// No description provided for @coViewCouldnTLoadFriendsTryAgain.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load friends — try again'**
  String get coViewCouldnTLoadFriendsTryAgain;

  /// No description provided for @coViewCouldnTSendTheInvitationTry.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t send the invitation — try again'**
  String get coViewCouldnTSendTheInvitationTry;

  /// No description provided for @coViewAddToYourCircle.
  ///
  /// In en, this message translates to:
  /// **'add them to your circle'**
  String get coViewAddToYourCircle;

  /// No description provided for @coViewTheyLlJoinAsSoonAs.
  ///
  /// In en, this message translates to:
  /// **'they\'ll join as soon as they accept — like any other co-viewing invitation.'**
  String get coViewTheyLlJoinAsSoonAs;

  /// No description provided for @coViewAllYourFriendsAreAlreadyHere.
  ///
  /// In en, this message translates to:
  /// **'all your friends are already here — add new ones first, then invite them from here.'**
  String get coViewAllYourFriendsAreAlreadyHere;

  /// No description provided for @coViewYourSharedDiaryWillLiveHere.
  ///
  /// In en, this message translates to:
  /// **'your shared diary will live here'**
  String get coViewYourSharedDiaryWillLiveHere;

  /// No description provided for @coViewLinkUpWithThePersonYou.
  ///
  /// In en, this message translates to:
  /// **'link up with the person you watch with — and your evenings, ratings and stats become shared'**
  String get coViewLinkUpWithThePersonYou;

  /// No description provided for @coViewLinkUp.
  ///
  /// In en, this message translates to:
  /// **'get connected'**
  String get coViewLinkUp;

  /// No description provided for @challengesChallengesAreComingSoon.
  ///
  /// In en, this message translates to:
  /// **'challenges are coming soon'**
  String get challengesChallengesAreComingSoon;

  /// No description provided for @challengesThisWeek.
  ///
  /// In en, this message translates to:
  /// **'this week'**
  String get challengesThisWeek;

  /// No description provided for @challengesAllYear.
  ///
  /// In en, this message translates to:
  /// **'all year'**
  String get challengesAllYear;

  /// No description provided for @challengesHowItSCounted.
  ///
  /// In en, this message translates to:
  /// **'how it\'s counted'**
  String get challengesHowItSCounted;

  /// No description provided for @challengesSmallGoalsForTheWeekAnd.
  ///
  /// In en, this message translates to:
  /// **'small goals for the week and the year. didn\'t get to them — they simply roll over to new ones'**
  String get challengesSmallGoalsForTheWeekAnd;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'notifications'**
  String get settingsNotifications;

  /// No description provided for @settingsMatchesFriendsStreakAndLevels.
  ///
  /// In en, this message translates to:
  /// **'matches, friends, streak and levels'**
  String get settingsMatchesFriendsStreakAndLevels;

  /// No description provided for @settingsLogMyEveningsToTheShared.
  ///
  /// In en, this message translates to:
  /// **'log my evenings to the shared diary'**
  String get settingsLogMyEveningsToTheShared;

  /// No description provided for @settingsAnEveningYouWatchedTogetherStill.
  ///
  /// In en, this message translates to:
  /// **'an evening you watched together still lands in the shared diary — this switch is only about what gets logged from your own evenings'**
  String get settingsAnEveningYouWatchedTogetherStill;

  /// No description provided for @settingsShowMyRating.
  ///
  /// In en, this message translates to:
  /// **'show my rating'**
  String get settingsShowMyRating;

  /// No description provided for @settingsShowMyNotes.
  ///
  /// In en, this message translates to:
  /// **'show my notes'**
  String get settingsShowMyNotes;

  /// No description provided for @settingsNotesAreTheMostPersonalThing.
  ///
  /// In en, this message translates to:
  /// **'notes are the most personal thing in a diary, so they\'re hidden by default'**
  String get settingsNotesAreTheMostPersonalThing;

  /// No description provided for @notifSettingsCouldnTLoadSettingsTryAgain.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load settings — try again'**
  String get notifSettingsCouldnTLoadSettingsTryAgain;

  /// No description provided for @notifSettingsCouldnTSaveTryAgain.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t save — try again'**
  String get notifSettingsCouldnTSaveTryAgain;

  /// No description provided for @notifSettingsWhichPushesYouDLikeTo.
  ///
  /// In en, this message translates to:
  /// **'which pushes you\'d like to get — the rest simply won\'t be sent.'**
  String get notifSettingsWhichPushesYouDLikeTo;

  /// No description provided for @coViewYouLlLeaveTheCircleThe.
  ///
  /// In en, this message translates to:
  /// **'you\'ll leave the circle — the others carry on, and what\'s already in your own diary stays where it is.'**
  String get coViewYouLlLeaveTheCircleThe;

  /// No description provided for @coViewButThePairSAlbumNotes.
  ///
  /// In en, this message translates to:
  /// **'but the pair\'s album — notes, capsules and the anniversary date — will disappear for both of you, and can\'t be brought back.'**
  String get coViewButThePairSAlbumNotes;

  /// No description provided for @coViewLeave.
  ///
  /// In en, this message translates to:
  /// **'leave'**
  String get coViewLeave;

  /// No description provided for @coViewEndLink.
  ///
  /// In en, this message translates to:
  /// **'end link'**
  String get coViewEndLink;

  /// No description provided for @coViewLeaveThisCircle.
  ///
  /// In en, this message translates to:
  /// **'leave this circle'**
  String get coViewLeaveThisCircle;

  /// No description provided for @coViewSuggestedToYou.
  ///
  /// In en, this message translates to:
  /// **'suggested to you'**
  String get coViewSuggestedToYou;

  /// No description provided for @coViewYourSharedDiary.
  ///
  /// In en, this message translates to:
  /// **'your shared diary'**
  String get coViewYourSharedDiary;

  /// No description provided for @coViewSuggested.
  ///
  /// In en, this message translates to:
  /// **'suggested by'**
  String get coViewSuggested;

  /// No description provided for @coViewTheListIsFullMarkSomething.
  ///
  /// In en, this message translates to:
  /// **'the list is full — mark something as watched to free up room'**
  String get coViewTheListIsFullMarkSomething;

  /// No description provided for @coViewUnlimitedSharedList.
  ///
  /// In en, this message translates to:
  /// **'unlimited shared list'**
  String get coViewUnlimitedSharedList;

  /// No description provided for @interestsWhatShouldWeGatherForYou.
  ///
  /// In en, this message translates to:
  /// **'what should we gather for you?'**
  String get interestsWhatShouldWeGatherForYou;

  /// No description provided for @interestsYourInterests.
  ///
  /// In en, this message translates to:
  /// **'your interests'**
  String get interestsYourInterests;

  /// No description provided for @interestsPickAFewThingsYouRe.
  ///
  /// In en, this message translates to:
  /// **'pick a few things you\'re into — collections will lead with those. you can always change your mind later.'**
  String get interestsPickAFewThingsYouRe;

  /// No description provided for @interestsChangeWhatCollectionsLeadsWithAny.
  ///
  /// In en, this message translates to:
  /// **'change what collections leads with, any time.'**
  String get interestsChangeWhatCollectionsLeadsWithAny;

  /// No description provided for @interestsChangeWhatTheReleaseCalendarShows.
  ///
  /// In en, this message translates to:
  /// **'change what the release calendar shows, any time.'**
  String get interestsChangeWhatTheReleaseCalendarShows;

  /// No description provided for @chChallengeComplete.
  ///
  /// In en, this message translates to:
  /// **'challenge complete'**
  String get chChallengeComplete;

  /// No description provided for @chChallenge.
  ///
  /// In en, this message translates to:
  /// **'challenge'**
  String get chChallenge;

  /// No description provided for @moreFriendsOnly.
  ///
  /// In en, this message translates to:
  /// **'friends only'**
  String get moreFriendsOnly;

  /// No description provided for @moreTrailersAreStillRunningPlentyOf.
  ///
  /// In en, this message translates to:
  /// **'trailers are still running — plenty of time'**
  String get moreTrailersAreStillRunningPlentyOf;

  /// No description provided for @moreSomeoneTwoRowsBackJustSettled.
  ///
  /// In en, this message translates to:
  /// **'someone two rows back just settled in with popcorn'**
  String get moreSomeoneTwoRowsBackJustSettled;

  /// No description provided for @moreTheCurtainHasnTPulledBack.
  ///
  /// In en, this message translates to:
  /// **'the curtain hasn\'t pulled back yet'**
  String get moreTheCurtainHasnTPulledBack;

  /// No description provided for @moreHouseLightsAreOnlyHalfDown.
  ///
  /// In en, this message translates to:
  /// **'house lights are only half down so far'**
  String get moreHouseLightsAreOnlyHalfDown;

  /// No description provided for @moreAFewSeatsAreStillFilling.
  ///
  /// In en, this message translates to:
  /// **'a few seats are still filling in around you'**
  String get moreAFewSeatsAreStillFilling;

  /// No description provided for @moreItSThatHushRightBefore.
  ///
  /// In en, this message translates to:
  /// **'it\'s that hush right before the reel starts'**
  String get moreItSThatHushRightBefore;

  /// No description provided for @moreTonightSLittleScreening.
  ///
  /// In en, this message translates to:
  /// **'tonight\'s little screening'**
  String get moreTonightSLittleScreening;

  /// No description provided for @moreRoughRide.
  ///
  /// In en, this message translates to:
  /// **'rough ride'**
  String get moreRoughRide;

  /// No description provided for @moreBumpyGoing.
  ///
  /// In en, this message translates to:
  /// **'bumpy going'**
  String get moreBumpyGoing;

  /// No description provided for @moreGladThatSOver.
  ///
  /// In en, this message translates to:
  /// **'glad that\'s over'**
  String get moreGladThatSOver;

  /// No description provided for @moreFineRide.
  ///
  /// In en, this message translates to:
  /// **'fine ride'**
  String get moreFineRide;

  /// No description provided for @moreDecentTrip.
  ///
  /// In en, this message translates to:
  /// **'decent trip'**
  String get moreDecentTrip;

  /// No description provided for @moreSmoothGoing.
  ///
  /// In en, this message translates to:
  /// **'smooth going'**
  String get moreSmoothGoing;

  /// No description provided for @moreReallyGoodRide.
  ///
  /// In en, this message translates to:
  /// **'really good ride'**
  String get moreReallyGoodRide;

  /// No description provided for @moreLovedThisRoute.
  ///
  /// In en, this message translates to:
  /// **'loved this route'**
  String get moreLovedThisRoute;

  /// No description provided for @moreOneForTheRegulars.
  ///
  /// In en, this message translates to:
  /// **'one for the regulars'**
  String get moreOneForTheRegulars;

  /// No description provided for @morePerfectJourney.
  ///
  /// In en, this message translates to:
  /// **'perfect journey'**
  String get morePerfectJourney;

  /// No description provided for @moreDriverJustToppedOffTheirCoffee.
  ///
  /// In en, this message translates to:
  /// **'driver just topped off their coffee — no rush yet'**
  String get moreDriverJustToppedOffTheirCoffee;

  /// No description provided for @moreSomeoneUpFrontIsAlreadyHalf.
  ///
  /// In en, this message translates to:
  /// **'someone up front is already half asleep'**
  String get moreSomeoneUpFrontIsAlreadyHalf;

  /// No description provided for @moreTheWindowSeatIsWarmFrom.
  ///
  /// In en, this message translates to:
  /// **'the window seat is warm from the last bit of sun'**
  String get moreTheWindowSeatIsWarmFrom;

  /// No description provided for @moreRadioSDownLowJustEnough.
  ///
  /// In en, this message translates to:
  /// **'radio\'s down low, just enough to notice'**
  String get moreRadioSDownLowJustEnough;

  /// No description provided for @moreAFewStragglersStillFindingTheir.
  ///
  /// In en, this message translates to:
  /// **'a few stragglers still finding their row'**
  String get moreAFewStragglersStillFindingTheir;

  /// No description provided for @moreTheRoadAheadLooksQuietTonight.
  ///
  /// In en, this message translates to:
  /// **'the road ahead looks quiet tonight'**
  String get moreTheRoadAheadLooksQuietTonight;

  /// No description provided for @moreTonightSRide.
  ///
  /// In en, this message translates to:
  /// **'tonight\'s ride'**
  String get moreTonightSRide;

  /// No description provided for @moreTapToRateTheRide.
  ///
  /// In en, this message translates to:
  /// **'tap to rate the ride'**
  String get moreTapToRateTheRide;

  /// No description provided for @moreDidnTTakeRoot.
  ///
  /// In en, this message translates to:
  /// **'didn\'t take root'**
  String get moreDidnTTakeRoot;

  /// No description provided for @moreWiltedEarly.
  ///
  /// In en, this message translates to:
  /// **'wilted early'**
  String get moreWiltedEarly;

  /// No description provided for @moreGladThatSDone.
  ///
  /// In en, this message translates to:
  /// **'glad that\'s done'**
  String get moreGladThatSDone;

  /// No description provided for @moreGrewOkay.
  ///
  /// In en, this message translates to:
  /// **'grew okay'**
  String get moreGrewOkay;

  /// No description provided for @moreDecentLittleSprout.
  ///
  /// In en, this message translates to:
  /// **'decent little sprout'**
  String get moreDecentLittleSprout;

  /// No description provided for @moreGrewWell.
  ///
  /// In en, this message translates to:
  /// **'grew well'**
  String get moreGrewWell;

  /// No description provided for @moreInFullBloom.
  ///
  /// In en, this message translates to:
  /// **'in full bloom'**
  String get moreInFullBloom;

  /// No description provided for @moreOneForTheGarden.
  ///
  /// In en, this message translates to:
  /// **'one for the garden'**
  String get moreOneForTheGarden;

  /// No description provided for @morePerfectBloom.
  ///
  /// In en, this message translates to:
  /// **'perfect bloom'**
  String get morePerfectBloom;

  /// No description provided for @moreTheSoilHereStillHoldsA.
  ///
  /// In en, this message translates to:
  /// **'the soil here still holds a bit of the day\'s warmth'**
  String get moreTheSoilHereStillHoldsA;

  /// No description provided for @moreAMothSBeenCirclingThe.
  ///
  /// In en, this message translates to:
  /// **'a moth\'s been circling the porch light all evening'**
  String get moreAMothSBeenCirclingThe;

  /// No description provided for @moreDewHasnTSettledOnThe.
  ///
  /// In en, this message translates to:
  /// **'dew hasn\'t settled on the leaves yet — still early'**
  String get moreDewHasnTSettledOnThe;

  /// No description provided for @moreSomethingNearbyJustStartedUpIts.
  ///
  /// In en, this message translates to:
  /// **'something nearby just started up its evening hum'**
  String get moreSomethingNearbyJustStartedUpIts;

  /// No description provided for @moreTheAirSmellsLikeItRained.
  ///
  /// In en, this message translates to:
  /// **'the air smells like it rained not long ago'**
  String get moreTheAirSmellsLikeItRained;

  /// No description provided for @moreTheLastBitOfDuskIs.
  ///
  /// In en, this message translates to:
  /// **'the last bit of dusk is caught in the leaves'**
  String get moreTheLastBitOfDuskIs;

  /// No description provided for @moreTonightSLittlePlanting.
  ///
  /// In en, this message translates to:
  /// **'tonight\'s little planting'**
  String get moreTonightSLittlePlanting;

  /// No description provided for @moreTapABudToRateIt.
  ///
  /// In en, this message translates to:
  /// **'tap a bud to rate it'**
  String get moreTapABudToRateIt;

  /// No description provided for @moreMainGate.
  ///
  /// In en, this message translates to:
  /// **'main gate'**
  String get moreMainGate;

  /// No description provided for @moreInBloom.
  ///
  /// In en, this message translates to:
  /// **'in bloom'**
  String get moreInBloom;

  /// No description provided for @moreThePad.
  ///
  /// In en, this message translates to:
  /// **'the pad'**
  String get moreThePad;

  /// No description provided for @moreAnyMomentNow.
  ///
  /// In en, this message translates to:
  /// **'any moment now'**
  String get moreAnyMomentNow;

  /// No description provided for @morePausedTapUpTopToKeep.
  ///
  /// In en, this message translates to:
  /// **'paused — tap ▶ up top to keep going'**
  String get morePausedTapUpTopToKeep;

  /// No description provided for @morePausedTapToKeepGoing.
  ///
  /// In en, this message translates to:
  /// **'paused — tap ▶ to keep going'**
  String get morePausedTapToKeepGoing;

  /// No description provided for @moreTheGateIsOpenChooseWhere.
  ///
  /// In en, this message translates to:
  /// **'the gate is open — choose where to wander tonight'**
  String get moreTheGateIsOpenChooseWhere;

  /// No description provided for @moreKeplerReach.
  ///
  /// In en, this message translates to:
  /// **'Kepler Reach'**
  String get moreKeplerReach;

  /// No description provided for @moreTheVelaCluster.
  ///
  /// In en, this message translates to:
  /// **'the Vela Cluster'**
  String get moreTheVelaCluster;

  /// No description provided for @moreProximaDock.
  ///
  /// In en, this message translates to:
  /// **'Proxima Dock'**
  String get moreProximaDock;

  /// No description provided for @moreTheLyraBelt.
  ///
  /// In en, this message translates to:
  /// **'the Lyra Belt'**
  String get moreTheLyraBelt;

  /// No description provided for @moreAuroraStation.
  ///
  /// In en, this message translates to:
  /// **'Aurora Station'**
  String get moreAuroraStation;

  /// No description provided for @moreTheCoalsackGate.
  ///
  /// In en, this message translates to:
  /// **'the Coalsack Gate'**
  String get moreTheCoalsackGate;

  /// No description provided for @moreHalcyonOrbit.
  ///
  /// In en, this message translates to:
  /// **'Halcyon Orbit'**
  String get moreHalcyonOrbit;

  /// No description provided for @moreThePerseusRim.
  ///
  /// In en, this message translates to:
  /// **'the Perseus Rim'**
  String get moreThePerseusRim;

  /// No description provided for @moreGroundCrewSStillDoingOne.
  ///
  /// In en, this message translates to:
  /// **'ground crew\'s still doing one last check outside'**
  String get moreGroundCrewSStillDoingOne;

  /// No description provided for @moreSomeoneInTheNextBerthIs.
  ///
  /// In en, this message translates to:
  /// **'someone in the next berth is already half asleep'**
  String get moreSomeoneInTheNextBerthIs;

  /// No description provided for @moreThePortholeIsWarmFromThe.
  ///
  /// In en, this message translates to:
  /// **'the porthole is warm from the launch lights'**
  String get moreThePortholeIsWarmFromThe;

  /// No description provided for @moreCommsAreDownLowJustEnough.
  ///
  /// In en, this message translates to:
  /// **'comms are down low, just enough to notice'**
  String get moreCommsAreDownLowJustEnough;

  /// No description provided for @moreAFewLateArrivalsStillFinding.
  ///
  /// In en, this message translates to:
  /// **'a few late arrivals still finding their berth'**
  String get moreAFewLateArrivalsStillFinding;

  /// No description provided for @moreTheSkyOutsideLooksQuietTonight.
  ///
  /// In en, this message translates to:
  /// **'the sky outside looks quiet tonight'**
  String get moreTheSkyOutsideLooksQuietTonight;

  /// No description provided for @moreARouteChosenAndBoardedNow.
  ///
  /// In en, this message translates to:
  /// **'a route, chosen and boarded now'**
  String get moreARouteChosenAndBoardedNow;

  /// No description provided for @moreACinemaFlownToAndPlaying.
  ///
  /// In en, this message translates to:
  /// **'a cinema, flown to and playing now'**
  String get moreACinemaFlownToAndPlaying;

  /// No description provided for @moreAGardenWalkedRightNow.
  ///
  /// In en, this message translates to:
  /// **'a garden, walked right now'**
  String get moreAGardenWalkedRightNow;

  /// No description provided for @moreALaunchSiteClearedAndLifting.
  ///
  /// In en, this message translates to:
  /// **'a launch site, cleared and lifting off now'**
  String get moreALaunchSiteClearedAndLifting;

  /// No description provided for @moreUsernameNeeds3CharactersPasswordNeeds.
  ///
  /// In en, this message translates to:
  /// **'username needs 3+ characters, password needs 6+'**
  String get moreUsernameNeeds3CharactersPasswordNeeds;

  /// No description provided for @moreWhatSTheMoodTonight.
  ///
  /// In en, this message translates to:
  /// **'what\'s the mood tonight?'**
  String get moreWhatSTheMoodTonight;

  /// No description provided for @moreAnyGenreInMind.
  ///
  /// In en, this message translates to:
  /// **'any genre in mind?'**
  String get moreAnyGenreInMind;

  /// No description provided for @moreAndRoughlyWhichEra.
  ///
  /// In en, this message translates to:
  /// **'and roughly which era?'**
  String get moreAndRoughlyWhichEra;

  /// No description provided for @morePickOneOrMoreToStart.
  ///
  /// In en, this message translates to:
  /// **'pick one or more to start narrowing'**
  String get morePickOneOrMoreToStart;

  /// No description provided for @moreBasedOnWhatYouJustPicked.
  ///
  /// In en, this message translates to:
  /// **'based on what you just picked'**
  String get moreBasedOnWhatYouJustPicked;

  /// No description provided for @moreOrLeaveItWideOpen.
  ///
  /// In en, this message translates to:
  /// **'or leave it wide open'**
  String get moreOrLeaveItWideOpen;

  /// No description provided for @moreYourDiaryIsWaiting.
  ///
  /// In en, this message translates to:
  /// **'your diary is waiting'**
  String get moreYourDiaryIsWaiting;

  /// No description provided for @more2010sSciFiGame.
  ///
  /// In en, this message translates to:
  /// **'2010s sci-fi game'**
  String get more2010sSciFiGame;

  /// No description provided for @moreCoOpGameForTwo.
  ///
  /// In en, this message translates to:
  /// **'co-op game for two'**
  String get moreCoOpGameForTwo;

  /// No description provided for @moreAYearAgoTodayYouWatched.
  ///
  /// In en, this message translates to:
  /// **'a year ago today, you watched'**
  String get moreAYearAgoTodayYouWatched;

  /// No description provided for @moreAMonthAgoTodayYouWatched.
  ///
  /// In en, this message translates to:
  /// **'a month ago today, you watched'**
  String get moreAMonthAgoTodayYouWatched;

  /// No description provided for @moreLinkWithAPartnerThenSuggest.
  ///
  /// In en, this message translates to:
  /// **'link with a partner, then suggest titles with one tap'**
  String get moreLinkWithAPartnerThenSuggest;

  /// No description provided for @moreProposeIt.
  ///
  /// In en, this message translates to:
  /// **'propose it'**
  String get moreProposeIt;

  /// No description provided for @moreCouldnTStartAVoteJust.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t start a vote just now — try again'**
  String get moreCouldnTStartAVoteJust;

  /// No description provided for @moreSomethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'something went wrong'**
  String get moreSomethingWentWrong;

  /// No description provided for @moreEveryoneHasVoted.
  ///
  /// In en, this message translates to:
  /// **'everyone has voted'**
  String get moreEveryoneHasVoted;

  /// No description provided for @moreWaitingOnTheOthers.
  ///
  /// In en, this message translates to:
  /// **'waiting on the others'**
  String get moreWaitingOnTheOthers;

  /// No description provided for @moreYouHavenTVotedYet.
  ///
  /// In en, this message translates to:
  /// **'you haven\'t voted yet'**
  String get moreYouHavenTVotedYet;

  /// No description provided for @moreItSDecided.
  ///
  /// In en, this message translates to:
  /// **'it\'s decided'**
  String get moreItSDecided;

  /// No description provided for @moreRoundClosed.
  ///
  /// In en, this message translates to:
  /// **'round closed'**
  String get moreRoundClosed;

  /// No description provided for @moreNoJustTakeTheWholePool.
  ///
  /// In en, this message translates to:
  /// **'no, just take the whole pool'**
  String get moreNoJustTakeTheWholePool;

  /// No description provided for @moreCouldnTStartARoundCheck.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t start a round — check your connection and try again'**
  String get moreCouldnTStartARoundCheck;

  /// No description provided for @moreAddAFewTitlesToYour.
  ///
  /// In en, this message translates to:
  /// **'add a few titles to your plan-to-watch shelves, or plan something together first'**
  String get moreAddAFewTitlesToYour;

  /// No description provided for @moreAddAFewTitlesToYour2.
  ///
  /// In en, this message translates to:
  /// **'add a few titles to your plan-to-watch shelves first, then come back to vote on them'**
  String get moreAddAFewTitlesToYour2;

  /// No description provided for @moreTypeAMovieTitleToSearch.
  ///
  /// In en, this message translates to:
  /// **'type a movie title to search'**
  String get moreTypeAMovieTitleToSearch;

  /// No description provided for @moreNoMoviesFound.
  ///
  /// In en, this message translates to:
  /// **'no movies found'**
  String get moreNoMoviesFound;

  /// No description provided for @moreTapTheStarOnUpTo.
  ///
  /// In en, this message translates to:
  /// **'tap the star on up to 5 to build your profile banner'**
  String get moreTapTheStarOnUpTo;

  /// No description provided for @moreTapAStarToAddOr.
  ///
  /// In en, this message translates to:
  /// **'tap a star to add or remove it from your profile banner'**
  String get moreTapAStarToAddOr;

  /// No description provided for @moreInBanner.
  ///
  /// In en, this message translates to:
  /// **'in banner'**
  String get moreInBanner;

  /// No description provided for @morePlexWebhookURL.
  ///
  /// In en, this message translates to:
  /// **'Plex webhook URL'**
  String get morePlexWebhookURL;

  /// No description provided for @morePickWhatYouUse.
  ///
  /// In en, this message translates to:
  /// **'pick what you use'**
  String get morePickWhatYouUse;

  /// No description provided for @moreAMediaServerKodiOrJust.
  ///
  /// In en, this message translates to:
  /// **'a media server, Kodi, or just a normal browser — see below'**
  String get moreAMediaServerKodiOrJust;

  /// No description provided for @morePasteOneLinkAndMaybeA.
  ///
  /// In en, this message translates to:
  /// **'paste one link (and maybe a code)'**
  String get morePasteOneLinkAndMaybeA;

  /// No description provided for @moreItSAlreadyFilledInFor.
  ///
  /// In en, this message translates to:
  /// **'it\'s already filled in for you — just copy and paste'**
  String get moreItSAlreadyFilledInFor;

  /// No description provided for @moreWatchThingsLikeNormal.
  ///
  /// In en, this message translates to:
  /// **'watch things like normal'**
  String get moreWatchThingsLikeNormal;

  /// No description provided for @moreFinishingSomethingLogsItHereAutomatically.
  ///
  /// In en, this message translates to:
  /// **'finishing something logs it here automatically from then on'**
  String get moreFinishingSomethingLogsItHereAutomatically;

  /// No description provided for @moreNoTitle.
  ///
  /// In en, this message translates to:
  /// **'(no title)'**
  String get moreNoTitle;

  /// No description provided for @moreNothingMarkedWatchedYet.
  ///
  /// In en, this message translates to:
  /// **'nothing marked watched yet'**
  String get moreNothingMarkedWatchedYet;

  /// No description provided for @moreNothingQueuedYetSearchToAdd.
  ///
  /// In en, this message translates to:
  /// **'nothing queued yet — search to add something'**
  String get moreNothingQueuedYetSearchToAdd;

  /// No description provided for @moreCouldnTLoadAchievementsRightNow.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load achievements right now'**
  String get moreCouldnTLoadAchievementsRightNow;

  /// No description provided for @moreNothingUnlockedYetKeepLogging.
  ///
  /// In en, this message translates to:
  /// **'nothing unlocked yet — keep logging'**
  String get moreNothingUnlockedYetKeepLogging;

  /// No description provided for @moreNothingInProgressRightNow.
  ///
  /// In en, this message translates to:
  /// **'nothing in progress right now'**
  String get moreNothingInProgressRightNow;

  /// No description provided for @moreNothingQueuedYet.
  ///
  /// In en, this message translates to:
  /// **'nothing queued yet'**
  String get moreNothingQueuedYet;

  /// No description provided for @moreWatchedOnce.
  ///
  /// In en, this message translates to:
  /// **'watched once'**
  String get moreWatchedOnce;

  /// No description provided for @moreSeriesAnime.
  ///
  /// In en, this message translates to:
  /// **'series & anime'**
  String get moreSeriesAnime;

  /// No description provided for @moreTitlesYouBothSaidYesTo.
  ///
  /// In en, this message translates to:
  /// **'titles you both said yes to'**
  String get moreTitlesYouBothSaidYesTo;

  /// No description provided for @moreEachOnYourOwnPhoneWhatever.
  ///
  /// In en, this message translates to:
  /// **'each on your own phone — whatever you both say yes to gets tucked into your \"watch together\" list, ready for movie night.'**
  String get moreEachOnYourOwnPhoneWhatever;

  /// No description provided for @morePassThePhoneOrJustLean.
  ///
  /// In en, this message translates to:
  /// **'pass the phone, or just lean in — whatever you both say yes to gets tucked into your \"watch together\" list, ready for movie night.'**
  String get morePassThePhoneOrJustLean;

  /// No description provided for @moreTuckedIntoYourWatchTogetherList.
  ///
  /// In en, this message translates to:
  /// **'tucked into your \"watch together\" list — pick tonight\'s from there.'**
  String get moreTuckedIntoYourWatchTogetherList;

  /// No description provided for @moreHappensSometimesTryADifferentMood.
  ///
  /// In en, this message translates to:
  /// **'happens sometimes — try a different mood, or shuffle again.'**
  String get moreHappensSometimesTryADifferentMood;

  /// No description provided for @moreTheRoseWalk.
  ///
  /// In en, this message translates to:
  /// **'the rose walk'**
  String get moreTheRoseWalk;

  /// No description provided for @moreTheShadedPath.
  ///
  /// In en, this message translates to:
  /// **'the shaded path'**
  String get moreTheShadedPath;

  /// No description provided for @moreTheWaterGarden.
  ///
  /// In en, this message translates to:
  /// **'the water garden'**
  String get moreTheWaterGarden;

  /// No description provided for @moreTheArboretumTrail.
  ///
  /// In en, this message translates to:
  /// **'the arboretum trail'**
  String get moreTheArboretumTrail;

  /// No description provided for @moreTheSunkenGarden.
  ///
  /// In en, this message translates to:
  /// **'the sunken garden'**
  String get moreTheSunkenGarden;

  /// No description provided for @moreTheOldOrchardRow.
  ///
  /// In en, this message translates to:
  /// **'the old orchard row'**
  String get moreTheOldOrchardRow;

  /// No description provided for @moreNextShowingSameHall.
  ///
  /// In en, this message translates to:
  /// **'next showing, same hall'**
  String get moreNextShowingSameHall;

  /// No description provided for @moreUnpinFromProfile.
  ///
  /// In en, this message translates to:
  /// **'unpin from profile'**
  String get moreUnpinFromProfile;

  /// No description provided for @morePinToProfile.
  ///
  /// In en, this message translates to:
  /// **'pin to profile'**
  String get morePinToProfile;

  /// No description provided for @moreWipeTheWindowToSee.
  ///
  /// In en, this message translates to:
  /// **'wipe the window to see'**
  String get moreWipeTheWindowToSee;

  /// No description provided for @moreTearItAtTheGateOr.
  ///
  /// In en, this message translates to:
  /// **'tear it at the gate — or just tap'**
  String get moreTearItAtTheGateOr;

  /// No description provided for @moreChallengeClaimed.
  ///
  /// In en, this message translates to:
  /// **'challenge claimed'**
  String get moreChallengeClaimed;

  /// No description provided for @moreASkylineWaitingToStart.
  ///
  /// In en, this message translates to:
  /// **'a skyline, waiting to start'**
  String get moreASkylineWaitingToStart;

  /// No description provided for @moreLogOneToSeeItRise.
  ///
  /// In en, this message translates to:
  /// **'log one to see it rise'**
  String get moreLogOneToSeeItRise;

  /// No description provided for @moreWalkTheStreetToSeeThem.
  ///
  /// In en, this message translates to:
  /// **'walk the street to see them all'**
  String get moreWalkTheStreetToSeeThem;

  /// No description provided for @moreCozyThatOneSYours.
  ///
  /// In en, this message translates to:
  /// **'cozy — that one\'s yours'**
  String get moreCozyThatOneSYours;

  /// No description provided for @moreTraceBackAnyEveningYouPassed.
  ///
  /// In en, this message translates to:
  /// **'trace back any evening you passed through'**
  String get moreTraceBackAnyEveningYouPassed;

  /// No description provided for @moreLogOneToPlantTheFirst.
  ///
  /// In en, this message translates to:
  /// **'log one to plant the first seed'**
  String get moreLogOneToPlantTheFirst;

  /// No description provided for @moreWalkTheWindowBoxToSee.
  ///
  /// In en, this message translates to:
  /// **'walk the window box to see every one'**
  String get moreWalkTheWindowBoxToSee;

  /// No description provided for @moreChooseASpotForTonight.
  ///
  /// In en, this message translates to:
  /// **'choose a spot for tonight'**
  String get moreChooseASpotForTonight;

  /// No description provided for @moreTuckingItIntoTheBed.
  ///
  /// In en, this message translates to:
  /// **'tucking it into the bed…'**
  String get moreTuckingItIntoTheBed;

  /// No description provided for @moreCollectionOfTheWeek.
  ///
  /// In en, this message translates to:
  /// **'collection of the week'**
  String get moreCollectionOfTheWeek;

  /// No description provided for @moreTheMusic.
  ///
  /// In en, this message translates to:
  /// **'the music'**
  String get moreTheMusic;

  /// No description provided for @moreTheEnding.
  ///
  /// In en, this message translates to:
  /// **'the ending'**
  String get moreTheEnding;

  /// No description provided for @moreTheAtmosphere.
  ///
  /// In en, this message translates to:
  /// **'the atmosphere'**
  String get moreTheAtmosphere;

  /// No description provided for @moreThePerformances.
  ///
  /// In en, this message translates to:
  /// **'the performances'**
  String get moreThePerformances;

  /// No description provided for @moreTheVisuals.
  ///
  /// In en, this message translates to:
  /// **'the visuals'**
  String get moreTheVisuals;

  /// No description provided for @moreTheStory.
  ///
  /// In en, this message translates to:
  /// **'the story'**
  String get moreTheStory;

  /// No description provided for @moreTheHumor.
  ///
  /// In en, this message translates to:
  /// **'the humor'**
  String get moreTheHumor;

  /// No description provided for @moreThePacing.
  ///
  /// In en, this message translates to:
  /// **'the pacing'**
  String get moreThePacing;

  /// No description provided for @moreSawItComing.
  ///
  /// In en, this message translates to:
  /// **'saw it coming'**
  String get moreSawItComing;

  /// No description provided for @moreFlatCharacters.
  ///
  /// In en, this message translates to:
  /// **'flat characters'**
  String get moreFlatCharacters;

  /// No description provided for @moreStyleOverSubstance.
  ///
  /// In en, this message translates to:
  /// **'style over substance'**
  String get moreStyleOverSubstance;

  /// No description provided for @moreRanTooLong.
  ///
  /// In en, this message translates to:
  /// **'ran too long'**
  String get moreRanTooLong;

  /// No description provided for @moreTheTone.
  ///
  /// In en, this message translates to:
  /// **'the tone'**
  String get moreTheTone;

  /// No description provided for @moreWhatFellShort.
  ///
  /// In en, this message translates to:
  /// **'what fell short?'**
  String get moreWhatFellShort;

  /// No description provided for @moreWhyDidYouLoveThis.
  ///
  /// In en, this message translates to:
  /// **'why did you love this?'**
  String get moreWhyDidYouLoveThis;

  /// No description provided for @moreABlankPassportWaiting.
  ///
  /// In en, this message translates to:
  /// **'a blank passport, waiting'**
  String get moreABlankPassportWaiting;

  /// No description provided for @moreLogOneToSeeItLand.
  ///
  /// In en, this message translates to:
  /// **'log one to see it land'**
  String get moreLogOneToSeeItLand;

  /// No description provided for @moreGiveItAFlipToSee.
  ///
  /// In en, this message translates to:
  /// **'give it a flip to see them all'**
  String get moreGiveItAFlipToSee;

  /// No description provided for @moreThereSaveItForTonight.
  ///
  /// In en, this message translates to:
  /// **'there — save it for tonight'**
  String get moreThereSaveItForTonight;

  /// No description provided for @moreMarkAsWatched.
  ///
  /// In en, this message translates to:
  /// **'mark as watched'**
  String get moreMarkAsWatched;

  /// No description provided for @moreStillOnYourPlanToWatch.
  ///
  /// In en, this message translates to:
  /// **'still on your plan to watch — mark it once you have'**
  String get moreStillOnYourPlanToWatch;

  /// No description provided for @morePlanToWatchPreview.
  ///
  /// In en, this message translates to:
  /// **'plan to watch preview'**
  String get morePlanToWatchPreview;

  /// No description provided for @moreTheReview.
  ///
  /// In en, this message translates to:
  /// **'the review'**
  String get moreTheReview;

  /// No description provided for @moreEveryWordOfIt.
  ///
  /// In en, this message translates to:
  /// **'every word of it'**
  String get moreEveryWordOfIt;

  /// No description provided for @moreAsLongAsYouWantNobody.
  ///
  /// In en, this message translates to:
  /// **'as long as you want — nobody\'s reading over your shoulder'**
  String get moreAsLongAsYouWantNobody;

  /// No description provided for @moreABlankBoard.
  ///
  /// In en, this message translates to:
  /// **'a blank board'**
  String get moreABlankBoard;

  /// No description provided for @moreLogOneToSeeItPosted.
  ///
  /// In en, this message translates to:
  /// **'log one to see it posted'**
  String get moreLogOneToSeeItPosted;

  /// No description provided for @moreTapForTheFullManifest.
  ///
  /// In en, this message translates to:
  /// **'tap for the full manifest'**
  String get moreTapForTheFullManifest;

  /// No description provided for @moreSomewhereInHere.
  ///
  /// In en, this message translates to:
  /// **'somewhere in here…'**
  String get moreSomewhereInHere;

  /// No description provided for @moreSeriesPreview.
  ///
  /// In en, this message translates to:
  /// **'series preview'**
  String get moreSeriesPreview;

  /// No description provided for @moreCouldnTLoadEpisodesTryAgain.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t load episodes — try again'**
  String get moreCouldnTLoadEpisodesTryAgain;

  /// No description provided for @moreNoEpisodeDataForThisOne.
  ///
  /// In en, this message translates to:
  /// **'no episode data for this one yet'**
  String get moreNoEpisodeDataForThisOne;

  /// No description provided for @moreNoReviewLeftForThisOne.
  ///
  /// In en, this message translates to:
  /// **'no review left for this one yet'**
  String get moreNoReviewLeftForThisOne;

  /// No description provided for @moreMightGiveThingsAway.
  ///
  /// In en, this message translates to:
  /// **'might give things away'**
  String get moreMightGiveThingsAway;

  /// No description provided for @moreLogOneToLightTheFirst.
  ///
  /// In en, this message translates to:
  /// **'log one to light the first bulb'**
  String get moreLogOneToLightTheFirst;

  /// No description provided for @moreTapForTonightSFullProgramme.
  ///
  /// In en, this message translates to:
  /// **'tap for tonight\'s full programme'**
  String get moreTapForTonightSFullProgramme;

  /// No description provided for @moreNotTheOne.
  ///
  /// In en, this message translates to:
  /// **'not the one'**
  String get moreNotTheOne;

  /// No description provided for @moreRoughSit.
  ///
  /// In en, this message translates to:
  /// **'rough sit'**
  String get moreRoughSit;

  /// No description provided for @moreJustOkay.
  ///
  /// In en, this message translates to:
  /// **'just okay'**
  String get moreJustOkay;

  /// No description provided for @moreDecentWatch.
  ///
  /// In en, this message translates to:
  /// **'decent watch'**
  String get moreDecentWatch;

  /// No description provided for @moreGenuinelyLikedIt.
  ///
  /// In en, this message translates to:
  /// **'genuinely liked it'**
  String get moreGenuinelyLikedIt;

  /// No description provided for @moreReallyGood.
  ///
  /// In en, this message translates to:
  /// **'really good'**
  String get moreReallyGood;

  /// No description provided for @moreLovedEveryMinute.
  ///
  /// In en, this message translates to:
  /// **'loved every minute'**
  String get moreLovedEveryMinute;

  /// No description provided for @moreOneForTheShelf.
  ///
  /// In en, this message translates to:
  /// **'one for the shelf'**
  String get moreOneForTheShelf;

  /// No description provided for @morePerfectShow.
  ///
  /// In en, this message translates to:
  /// **'perfect show'**
  String get morePerfectShow;

  /// No description provided for @moreTapAHeartToRateIt.
  ///
  /// In en, this message translates to:
  /// **'tap a heart to rate it'**
  String get moreTapAHeartToRateIt;

  /// No description provided for @moreWatchComplete.
  ///
  /// In en, this message translates to:
  /// **'watch complete'**
  String get moreWatchComplete;

  /// No description provided for @moreWatchedPreview.
  ///
  /// In en, this message translates to:
  /// **'watched preview'**
  String get moreWatchedPreview;

  /// Plural: year / years — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} year} other {{count} years}}'**
  String nYears(int count);

  /// Plural: month / months — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} month} other {{count} months}}'**
  String nMonths(int count);

  /// Plural: time / times (as in "watched 3 times") — count + noun.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one {{count} time} other {{count} times}}'**
  String nTimes(int count);

  /// No description provided for @moreNoMatchesThisRoundTryAgain.
  ///
  /// In en, this message translates to:
  /// **'no matches this round — try again with a different mood.'**
  String get moreNoMatchesThisRoundTryAgain;

  /// No description provided for @moreWatchAll.
  ///
  /// In en, this message translates to:
  /// **'watch all →'**
  String get moreWatchAll;

  /// No description provided for @moreTapToSeeOrSuggest.
  ///
  /// In en, this message translates to:
  /// **'tap to see or suggest'**
  String get moreTapToSeeOrSuggest;

  /// No description provided for @moreTapToGetStarted.
  ///
  /// In en, this message translates to:
  /// **'tap to get started'**
  String get moreTapToGetStarted;

  /// No description provided for @moreThisRemovesYourRatingReviewAnd.
  ///
  /// In en, this message translates to:
  /// **'this removes your rating, review, and episode progress for this show — it\'ll drop back to plan to watch.'**
  String get moreThisRemovesYourRatingReviewAnd;

  /// No description provided for @moreThisRemovesYourRatingAndReview.
  ///
  /// In en, this message translates to:
  /// **'this removes your rating and review for this evening. if it\'s the only time you logged this title, it\'ll drop back to plan to watch.'**
  String get moreThisRemovesYourRatingAndReview;

  /// No description provided for @moreWhoStoodOutPickUpTo.
  ///
  /// In en, this message translates to:
  /// **'who stood out? pick up to 3'**
  String get moreWhoStoodOutPickUpTo;

  /// No description provided for @moreTheReelDrawsFromWhicheverPool.
  ///
  /// In en, this message translates to:
  /// **'the reel draws from whichever pool you pick, then everyone votes on where it lands.'**
  String get moreTheReelDrawsFromWhicheverPool;

  /// No description provided for @moreOneTitleGetsDrawnFromWhichever.
  ///
  /// In en, this message translates to:
  /// **'one title gets drawn from whichever pool you pick, then everyone votes on it.'**
  String get moreOneTitleGetsDrawnFromWhichever;

  /// No description provided for @moreYourSessionHasEndedPleaseSign.
  ///
  /// In en, this message translates to:
  /// **'your session has ended — please sign in again'**
  String get moreYourSessionHasEndedPleaseSign;

  /// No description provided for @morePickUpTo3TotallyOptional.
  ///
  /// In en, this message translates to:
  /// **'pick up to 3 — totally optional'**
  String get morePickUpTo3TotallyOptional;

  /// No description provided for @moreFindingRoutes.
  ///
  /// In en, this message translates to:
  /// **'finding routes…'**
  String get moreFindingRoutes;

  /// No description provided for @moreAnythingAnyYear.
  ///
  /// In en, this message translates to:
  /// **'anything, any year'**
  String get moreAnythingAnyYear;

  /// No description provided for @moreThereBuildHere.
  ///
  /// In en, this message translates to:
  /// **'there — build here'**
  String get moreThereBuildHere;

  /// No description provided for @moreLogAnEveningToLayThe.
  ///
  /// In en, this message translates to:
  /// **'log an evening to lay the first stretch of road'**
  String get moreLogAnEveningToLayThe;

  /// No description provided for @moreJellyfinWebhookURL.
  ///
  /// In en, this message translates to:
  /// **'Jellyfin webhook URL'**
  String get moreJellyfinWebhookURL;

  /// No description provided for @moreServerURL.
  ///
  /// In en, this message translates to:
  /// **'server URL'**
  String get moreServerURL;

  /// No description provided for @pushFriendsAreWatching.
  ///
  /// In en, this message translates to:
  /// **'friends are watching'**
  String get pushFriendsAreWatching;

  /// No description provided for @pushWhenAFriendRatesSomething.
  ///
  /// In en, this message translates to:
  /// **'when a friend rates something new'**
  String get pushWhenAFriendRatesSomething;

  /// No description provided for @pushFriendRequests.
  ///
  /// In en, this message translates to:
  /// **'friend requests'**
  String get pushFriendRequests;

  /// No description provided for @pushWhenSomeoneWantsToBe.
  ///
  /// In en, this message translates to:
  /// **'when someone wants to be your friend'**
  String get pushWhenSomeoneWantsToBe;

  /// No description provided for @pushPartner.
  ///
  /// In en, this message translates to:
  /// **'partner'**
  String get pushPartner;

  /// No description provided for @pushActivityFromYourLinkedAccount.
  ///
  /// In en, this message translates to:
  /// **'activity from your linked account'**
  String get pushActivityFromYourLinkedAccount;

  /// No description provided for @pushMatches.
  ///
  /// In en, this message translates to:
  /// **'matches'**
  String get pushMatches;

  /// No description provided for @pushWhenYouBothPickedThe.
  ///
  /// In en, this message translates to:
  /// **'when you both picked the same movie'**
  String get pushWhenYouBothPickedThe;

  /// No description provided for @pushLevels.
  ///
  /// In en, this message translates to:
  /// **'levels'**
  String get pushLevels;

  /// No description provided for @pushWhenYouReachANew.
  ///
  /// In en, this message translates to:
  /// **'when you reach a new level'**
  String get pushWhenYouReachANew;

  /// No description provided for @pushStreakReminders.
  ///
  /// In en, this message translates to:
  /// **'streak reminders'**
  String get pushStreakReminders;

  /// No description provided for @pushInTheEveningIfYour.
  ///
  /// In en, this message translates to:
  /// **'in the evening, if your streak is at risk'**
  String get pushInTheEveningIfYour;

  /// No description provided for @pushMemories.
  ///
  /// In en, this message translates to:
  /// **'memories'**
  String get pushMemories;

  /// No description provided for @pushAYearAgoYouWatched.
  ///
  /// In en, this message translates to:
  /// **'“a year ago you watched…”'**
  String get pushAYearAgoYouWatched;

  /// No description provided for @pushWhenAnEpisodeOrRelease.
  ///
  /// In en, this message translates to:
  /// **'when an episode or release comes out for something you track'**
  String get pushWhenAnEpisodeOrRelease;

  /// No description provided for @pushSubscription.
  ///
  /// In en, this message translates to:
  /// **'subscription'**
  String get pushSubscription;

  /// No description provided for @pushTheEndOfTheFree.
  ///
  /// In en, this message translates to:
  /// **'the end of the free period, pauses and subscription offers'**
  String get pushTheEndOfTheFree;

  /// No description provided for @pushOurAlbum.
  ///
  /// In en, this message translates to:
  /// **'our album'**
  String get pushOurAlbum;

  /// No description provided for @pushNotesCapsulesAndAnniversariesFor.
  ///
  /// In en, this message translates to:
  /// **'notes, capsules and anniversaries for two'**
  String get pushNotesCapsulesAndAnniversariesFor;

  /// No description provided for @pushWhenYouReInvitedInto.
  ///
  /// In en, this message translates to:
  /// **'when you\'re invited into a co-viewing room'**
  String get pushWhenYouReInvitedInto;

  /// No description provided for @errCouldNotValidateCredentials.
  ///
  /// In en, this message translates to:
  /// **'could not validate credentials'**
  String get errCouldNotValidateCredentials;

  /// No description provided for @errSessionExpiredSignInAgain.
  ///
  /// In en, this message translates to:
  /// **'session expired — sign in again'**
  String get errSessionExpiredSignInAgain;

  /// No description provided for @errAdminAccessRequired.
  ///
  /// In en, this message translates to:
  /// **'admin access required'**
  String get errAdminAccessRequired;

  /// No description provided for @errTooManyRequestsTryAgain.
  ///
  /// In en, this message translates to:
  /// **'too many requests — try again in a bit'**
  String get errTooManyRequestsTryAgain;

  /// No description provided for @errUsernameAlreadyTaken.
  ///
  /// In en, this message translates to:
  /// **'username already taken'**
  String get errUsernameAlreadyTaken;

  /// No description provided for @errPasswordIsTooLong.
  ///
  /// In en, this message translates to:
  /// **'password is too long'**
  String get errPasswordIsTooLong;

  /// No description provided for @errInvalidUsernameOrPassword.
  ///
  /// In en, this message translates to:
  /// **'invalid username or password'**
  String get errInvalidUsernameOrPassword;

  /// No description provided for @errCurrentPasswordIsIncorrect.
  ///
  /// In en, this message translates to:
  /// **'current password is incorrect'**
  String get errCurrentPasswordIsIncorrect;

  /// No description provided for @errThatSThePasswordYou.
  ///
  /// In en, this message translates to:
  /// **'that\'s the password you already have'**
  String get errThatSThePasswordYou;

  /// No description provided for @errThatResetLinkHasExpired.
  ///
  /// In en, this message translates to:
  /// **'that reset link has expired — request a new one'**
  String get errThatResetLinkHasExpired;

  /// No description provided for @errThatResetLinkWasAlready.
  ///
  /// In en, this message translates to:
  /// **'that reset link was already used'**
  String get errThatResetLinkWasAlready;

  /// No description provided for @errThatResetLinkIsNo.
  ///
  /// In en, this message translates to:
  /// **'that reset link is no longer valid'**
  String get errThatResetLinkIsNo;

  /// No description provided for @errPasswordIsIncorrect.
  ///
  /// In en, this message translates to:
  /// **'password is incorrect'**
  String get errPasswordIsIncorrect;

  /// No description provided for @errThatAddressIsAlreadyOn.
  ///
  /// In en, this message translates to:
  /// **'that address is already on another account'**
  String get errThatAddressIsAlreadyOn;

  /// No description provided for @errThatLinkHasExpiredRequest.
  ///
  /// In en, this message translates to:
  /// **'that link has expired — request a new one'**
  String get errThatLinkHasExpiredRequest;

  /// No description provided for @errThatAddressIsAlreadyConfirmed.
  ///
  /// In en, this message translates to:
  /// **'that address is already confirmed'**
  String get errThatAddressIsAlreadyConfirmed;

  /// No description provided for @errThatLinkIsNoLonger.
  ///
  /// In en, this message translates to:
  /// **'that link is no longer valid'**
  String get errThatLinkIsNoLonger;

  /// No description provided for @errThatLinkWasForA.
  ///
  /// In en, this message translates to:
  /// **'that link was for a different address'**
  String get errThatLinkWasForA;

  /// No description provided for @errThatAccountIsnTScheduled.
  ///
  /// In en, this message translates to:
  /// **'that account isn\'t scheduled for deletion'**
  String get errThatAccountIsnTScheduled;

  /// No description provided for @errNoSuchChallengeRunningRight.
  ///
  /// In en, this message translates to:
  /// **'no such challenge running right now'**
  String get errNoSuchChallengeRunningRight;

  /// No description provided for @errNotFinishedYet.
  ///
  /// In en, this message translates to:
  /// **'not finished yet'**
  String get errNotFinishedYet;

  /// No description provided for @errAlreadyCollected.
  ///
  /// In en, this message translates to:
  /// **'already collected'**
  String get errAlreadyCollected;

  /// No description provided for @errLinkWithAPartnerFirst.
  ///
  /// In en, this message translates to:
  /// **'link with a partner first'**
  String get errLinkWithAPartnerFirst;

  /// No description provided for @errPollNotFound.
  ///
  /// In en, this message translates to:
  /// **'poll not found'**
  String get errPollNotFound;

  /// No description provided for @errNeedAtLeastTwoTitles.
  ///
  /// In en, this message translates to:
  /// **'need at least two titles queued to vote between'**
  String get errNeedAtLeastTwoTitles;

  /// No description provided for @errThisPollIsAlreadyDone.
  ///
  /// In en, this message translates to:
  /// **'this poll is already done'**
  String get errThisPollIsAlreadyDone;

  /// No description provided for @errThatSNotOneOf.
  ///
  /// In en, this message translates to:
  /// **'that\'s not one of this round\'s options anymore'**
  String get errThatSNotOneOf;

  /// No description provided for @errRoundNotFound.
  ///
  /// In en, this message translates to:
  /// **'round not found'**
  String get errRoundNotFound;

  /// No description provided for @errNothingToPropose.
  ///
  /// In en, this message translates to:
  /// **'nothing to propose'**
  String get errNothingToPropose;

  /// No description provided for @errThisRoundIsAlreadyDone.
  ///
  /// In en, this message translates to:
  /// **'this round is already done'**
  String get errThisRoundIsAlreadyDone;

  /// No description provided for @errDiaryEntryNotFound.
  ///
  /// In en, this message translates to:
  /// **'diary entry not found'**
  String get errDiaryEntryNotFound;

  /// No description provided for @errThatSYourOwnUsername.
  ///
  /// In en, this message translates to:
  /// **'that\'s your own username'**
  String get errThatSYourOwnUsername;

  /// No description provided for @errAlreadyFriends.
  ///
  /// In en, this message translates to:
  /// **'already friends'**
  String get errAlreadyFriends;

  /// No description provided for @errARequestIsAlreadyPending.
  ///
  /// In en, this message translates to:
  /// **'a request is already pending between you two'**
  String get errARequestIsAlreadyPending;

  /// No description provided for @errRequestNotFound.
  ///
  /// In en, this message translates to:
  /// **'request not found'**
  String get errRequestNotFound;

  /// No description provided for @errThatRequestWasAlreadyAnswered.
  ///
  /// In en, this message translates to:
  /// **'that request was already answered'**
  String get errThatRequestWasAlreadyAnswered;

  /// No description provided for @errNotFriendsWithThatAccount.
  ///
  /// In en, this message translates to:
  /// **'not friends with that account'**
  String get errNotFriendsWithThatAccount;

  /// No description provided for @errNoSuchAccount.
  ///
  /// In en, this message translates to:
  /// **'no such account'**
  String get errNoSuchAccount;

  /// No description provided for @errThatSYourOwnAccount.
  ///
  /// In en, this message translates to:
  /// **'that\'s your own account'**
  String get errThatSYourOwnAccount;

  /// No description provided for @errNoSuchUser.
  ///
  /// In en, this message translates to:
  /// **'no such user'**
  String get errNoSuchUser;

  /// No description provided for @errNotEnoughShelfDataOn.
  ///
  /// In en, this message translates to:
  /// **'not enough shelf data on one or both sides yet'**
  String get errNotEnoughShelfDataOn;

  /// No description provided for @errNothingToImportPasteOne.
  ///
  /// In en, this message translates to:
  /// **'nothing to import — paste one title per line, or a csv export'**
  String get errNothingToImportPasteOne;

  /// No description provided for @errNothingToImport.
  ///
  /// In en, this message translates to:
  /// **'nothing to import'**
  String get errNothingToImport;

  /// No description provided for @errUnknownIntegrationToken.
  ///
  /// In en, this message translates to:
  /// **'unknown integration token'**
  String get errUnknownIntegrationToken;

  /// No description provided for @errListNotFound.
  ///
  /// In en, this message translates to:
  /// **'list not found'**
  String get errListNotFound;

  /// No description provided for @errItemNotInThisList.
  ///
  /// In en, this message translates to:
  /// **'item not in this list'**
  String get errItemNotInThisList;

  /// No description provided for @errTitleNotFound.
  ///
  /// In en, this message translates to:
  /// **'title not found'**
  String get errTitleNotFound;

  /// No description provided for @errPersonNotFound.
  ///
  /// In en, this message translates to:
  /// **'person not found'**
  String get errPersonNotFound;

  /// No description provided for @errYouCanTBlockYourself.
  ///
  /// In en, this message translates to:
  /// **'you can\'t block yourself'**
  String get errYouCanTBlockYourself;

  /// No description provided for @errThatAccountIsnTBlocked.
  ///
  /// In en, this message translates to:
  /// **'that account isn\'t blocked'**
  String get errThatAccountIsnTBlocked;

  /// No description provided for @errUnknownReportTarget.
  ///
  /// In en, this message translates to:
  /// **'unknown report target'**
  String get errUnknownReportTarget;

  /// No description provided for @errUnknownReportReason.
  ///
  /// In en, this message translates to:
  /// **'unknown report reason'**
  String get errUnknownReportReason;

  /// No description provided for @errYouCanTReportYourself.
  ///
  /// In en, this message translates to:
  /// **'you can\'t report yourself'**
  String get errYouCanTReportYourself;

  /// No description provided for @errNoSuchReport.
  ///
  /// In en, this message translates to:
  /// **'no such report'**
  String get errNoSuchReport;

  /// No description provided for @errThatReportIsAlreadyResolved.
  ///
  /// In en, this message translates to:
  /// **'that report is already resolved'**
  String get errThatReportIsAlreadyResolved;

  /// No description provided for @errNotFound.
  ///
  /// In en, this message translates to:
  /// **'not found'**
  String get errNotFound;

  /// No description provided for @errYouAlreadyHaveAPartner.
  ///
  /// In en, this message translates to:
  /// **'you already have a partner linked'**
  String get errYouAlreadyHaveAPartner;

  /// No description provided for @errThatCodeDoesnTMatch.
  ///
  /// In en, this message translates to:
  /// **'that code doesn\'t match anything'**
  String get errThatCodeDoesnTMatch;

  /// No description provided for @errThatSYourOwnCode.
  ///
  /// In en, this message translates to:
  /// **'that\'s your own code — send it to them instead'**
  String get errThatSYourOwnCode;

  /// No description provided for @errThatCodeHasAlreadyBeen.
  ///
  /// In en, this message translates to:
  /// **'that code has already been used'**
  String get errThatCodeHasAlreadyBeen;

  /// No description provided for @errThatSYou.
  ///
  /// In en, this message translates to:
  /// **'that\'s you'**
  String get errThatSYou;

  /// No description provided for @errNoSuchInvite.
  ///
  /// In en, this message translates to:
  /// **'no such invite'**
  String get errNoSuchInvite;

  /// No description provided for @errThatInviteIsnTPending.
  ///
  /// In en, this message translates to:
  /// **'that invite isn\'t pending anymore'**
  String get errThatInviteIsnTPending;

  /// No description provided for @errLeaveYourCurrentCircleFirst.
  ///
  /// In en, this message translates to:
  /// **'leave your current circle first'**
  String get errLeaveYourCurrentCircleFirst;

  /// No description provided for @errSuggestionNotFound.
  ///
  /// In en, this message translates to:
  /// **'suggestion not found'**
  String get errSuggestionNotFound;

  /// No description provided for @errUnknownAvatarPreset.
  ///
  /// In en, this message translates to:
  /// **'unknown avatar preset'**
  String get errUnknownAvatarPreset;

  /// No description provided for @errDuplicatePick.
  ///
  /// In en, this message translates to:
  /// **'duplicate pick'**
  String get errDuplicatePick;

  /// No description provided for @errNotOneOfYourFavorite.
  ///
  /// In en, this message translates to:
  /// **'not one of your favorite films'**
  String get errNotOneOfYourFavorite;

  /// No description provided for @errUseAJpegPngOr.
  ///
  /// In en, this message translates to:
  /// **'use a jpeg, png, or webp image'**
  String get errUseAJpegPngOr;

  /// No description provided for @errImageIsLargerThan5.
  ///
  /// In en, this message translates to:
  /// **'image is larger than 5 mb'**
  String get errImageIsLargerThan5;

  /// No description provided for @errFileContentDoesnTMatch.
  ///
  /// In en, this message translates to:
  /// **'file content doesn\'t match a jpeg, png, or webp image'**
  String get errFileContentDoesnTMatch;

  /// No description provided for @errAlreadyAtTheMaximumNumber.
  ///
  /// In en, this message translates to:
  /// **'already at the maximum number of slots'**
  String get errAlreadyAtTheMaximumNumber;

  /// No description provided for @errReadingProgressIsOnlyKept.
  ///
  /// In en, this message translates to:
  /// **'reading progress is only kept for books and manga'**
  String get errReadingProgressIsOnlyKept;

  /// No description provided for @errCanTStakeARecommendation.
  ///
  /// In en, this message translates to:
  /// **'can\'t stake a recommendation to yourself'**
  String get errCanTStakeARecommendation;

  /// No description provided for @errNotFriendsWithThisPerson.
  ///
  /// In en, this message translates to:
  /// **'not friends with this person'**
  String get errNotFriendsWithThisPerson;

  /// No description provided for @errFriendNotFound.
  ///
  /// In en, this message translates to:
  /// **'friend not found'**
  String get errFriendNotFound;

  /// No description provided for @errAlreadyStakedOnThisTitle.
  ///
  /// In en, this message translates to:
  /// **'already staked on this title for this friend'**
  String get errAlreadyStakedOnThisTitle;

  /// No description provided for @errReferralNotFound.
  ///
  /// In en, this message translates to:
  /// **'referral not found'**
  String get errReferralNotFound;

  /// No description provided for @errThisEveningWasWatchedTogether.
  ///
  /// In en, this message translates to:
  /// **'this evening was watched together — delete it instead of hiding it'**
  String get errThisEveningWasWatchedTogether;

  /// No description provided for @errNothingToRevealHere.
  ///
  /// In en, this message translates to:
  /// **'nothing to reveal here'**
  String get errNothingToRevealHere;

  /// No description provided for @errNotInYourSharedPlans.
  ///
  /// In en, this message translates to:
  /// **'not in your shared plans'**
  String get errNotInYourSharedPlans;

  /// No description provided for @errTooSoonToNudgeAbout.
  ///
  /// In en, this message translates to:
  /// **'too soon to nudge about this one'**
  String get errTooSoonToNudgeAbout;

  /// No description provided for @errAlreadyNudgedRecently.
  ///
  /// In en, this message translates to:
  /// **'already nudged recently'**
  String get errAlreadyNudgedRecently;

  /// No description provided for @errThatDoesnTLookLike.
  ///
  /// In en, this message translates to:
  /// **'that doesn\'t look like a youtube or twitch link'**
  String get errThatDoesnTLookLike;

  /// No description provided for @errPasteALinkFirst.
  ///
  /// In en, this message translates to:
  /// **'paste a link first'**
  String get errPasteALinkFirst;

  /// No description provided for @errCollectionNotFound.
  ///
  /// In en, this message translates to:
  /// **'collection not found'**
  String get errCollectionNotFound;

  /// No description provided for @errItemNotFoundInThis.
  ///
  /// In en, this message translates to:
  /// **'item not found in this collection'**
  String get errItemNotFoundInThis;

  /// No description provided for @errThatTitleIsAlreadyIn.
  ///
  /// In en, this message translates to:
  /// **'that title is already in this collection'**
  String get errThatTitleIsAlreadyIn;

  /// No description provided for @errSessionNotFound.
  ///
  /// In en, this message translates to:
  /// **'session not found'**
  String get errSessionNotFound;

  /// No description provided for @errNotAParticipantInThis.
  ///
  /// In en, this message translates to:
  /// **'not a participant in this session'**
  String get errNotAParticipantInThis;

  /// No description provided for @errThatCodeDoesnTMatch2.
  ///
  /// In en, this message translates to:
  /// **'that code doesn\'t match a session'**
  String get errThatCodeDoesnTMatch2;

  /// No description provided for @errThatSYourOwnCode2.
  ///
  /// In en, this message translates to:
  /// **'that\'s your own code — send it to the other person'**
  String get errThatSYourOwnCode2;

  /// No description provided for @errThisSessionHasEnded.
  ///
  /// In en, this message translates to:
  /// **'this session has ended'**
  String get errThisSessionHasEnded;

  /// No description provided for @errSomeoneAlreadyJoinedThisSession.
  ///
  /// In en, this message translates to:
  /// **'someone already joined this session'**
  String get errSomeoneAlreadyJoinedThisSession;

  /// No description provided for @errThisCodeHasExpiredAsk.
  ///
  /// In en, this message translates to:
  /// **'this code has expired — ask for a new one'**
  String get errThisCodeHasExpiredAsk;

  /// No description provided for @errSessionIsnTActive.
  ///
  /// In en, this message translates to:
  /// **'session isn\'t active'**
  String get errSessionIsnTActive;

  /// No description provided for @errNotOnYourWatchlist.
  ///
  /// In en, this message translates to:
  /// **'not on your watchlist'**
  String get errNotOnYourWatchlist;

  /// No description provided for @errNothingToDropFromThis.
  ///
  /// In en, this message translates to:
  /// **'nothing to drop from this status'**
  String get errNothingToDropFromThis;

  /// No description provided for @errOnlyAPlannedItemCan.
  ///
  /// In en, this message translates to:
  /// **'only a planned item can owe debt'**
  String get errOnlyAPlannedItemCan;

  /// No description provided for @errAlreadySettled.
  ///
  /// In en, this message translates to:
  /// **'already settled'**
  String get errAlreadySettled;

  /// No description provided for @errNothingOwedOnThisOne.
  ///
  /// In en, this message translates to:
  /// **'nothing owed on this one yet'**
  String get errNothingOwedOnThisOne;

  /// No description provided for @errReviewNotFound.
  ///
  /// In en, this message translates to:
  /// **'review not found'**
  String get errReviewNotFound;

  /// No description provided for @errTheBookOfYourEvenings.
  ///
  /// In en, this message translates to:
  /// **'the book of your evenings unlocks with a subscription'**
  String get errTheBookOfYourEvenings;

  /// No description provided for @errYouWerenTAtThis.
  ///
  /// In en, this message translates to:
  /// **'you weren\'t at this evening'**
  String get errYouWerenTAtThis;

  /// No description provided for @errAddARatingTagsOr.
  ///
  /// In en, this message translates to:
  /// **'add a rating, tags or a few words — or skip'**
  String get errAddARatingTagsOr;

  /// No description provided for @errTheReviewIsAlreadyOpen.
  ///
  /// In en, this message translates to:
  /// **'the review is already open — it can only be read'**
  String get errTheReviewIsAlreadyOpen;

  /// No description provided for @errRoomNotFound.
  ///
  /// In en, this message translates to:
  /// **'room not found'**
  String get errRoomNotFound;

  /// No description provided for @errOnlyPeopleInTheCircle.
  ///
  /// In en, this message translates to:
  /// **'only people in the circle can do this'**
  String get errOnlyPeopleInTheCircle;

  /// No description provided for @errJoinTheRoomFirst.
  ///
  /// In en, this message translates to:
  /// **'join the room first'**
  String get errJoinTheRoomFirst;

  /// No description provided for @errUnknownMediaType.
  ///
  /// In en, this message translates to:
  /// **'unknown media type'**
  String get errUnknownMediaType;

  /// No description provided for @errUnknownRoomKind.
  ///
  /// In en, this message translates to:
  /// **'unknown room kind'**
  String get errUnknownRoomKind;

  /// No description provided for @errBooksAndMangaCanBe.
  ///
  /// In en, this message translates to:
  /// **'books and manga can be read together'**
  String get errBooksAndMangaCanBe;

  /// No description provided for @errGamesCanBePlayedTogether.
  ///
  /// In en, this message translates to:
  /// **'games can be played together'**
  String get errGamesCanBePlayedTogether;

  /// No description provided for @errARoomHoldsAtMost.
  ///
  /// In en, this message translates to:
  /// **'a room holds at most four people'**
  String get errARoomHoldsAtMost;

  /// No description provided for @errCouldnTOpenTheRoom.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t open the room — try again'**
  String get errCouldnTOpenTheRoom;

  /// No description provided for @errTheViewingHasAlreadyEnded.
  ///
  /// In en, this message translates to:
  /// **'the viewing has already ended'**
  String get errTheViewingHasAlreadyEnded;

  /// No description provided for @errUnknownAction.
  ///
  /// In en, this message translates to:
  /// **'unknown action'**
  String get errUnknownAction;

  /// No description provided for @errThereSNoPauseIn.
  ///
  /// In en, this message translates to:
  /// **'there\'s no pause in reading — just keep turning pages'**
  String get errThereSNoPauseIn;

  /// No description provided for @errInAGameTimeRuns.
  ///
  /// In en, this message translates to:
  /// **'in a game time runs by itself — you can play or take a break'**
  String get errInAGameTimeRuns;

  /// No description provided for @errUnknownEventType.
  ///
  /// In en, this message translates to:
  /// **'unknown event type'**
  String get errUnknownEventType;

  /// No description provided for @errUnknownOption.
  ///
  /// In en, this message translates to:
  /// **'unknown option'**
  String get errUnknownOption;

  /// No description provided for @errNotesAndHighlightsExistOnly.
  ///
  /// In en, this message translates to:
  /// **'notes and highlights exist only in reading'**
  String get errNotesAndHighlightsExistOnly;

  /// No description provided for @errRoundsExistOnlyInGames.
  ///
  /// In en, this message translates to:
  /// **'rounds exist only in games'**
  String get errRoundsExistOnlyInGames;

  /// No description provided for @errGamesHaveNoZenMode.
  ///
  /// In en, this message translates to:
  /// **'games have no zen mode'**
  String get errGamesHaveNoZenMode;

  /// No description provided for @errThisRoomHasNoSuch.
  ///
  /// In en, this message translates to:
  /// **'this room has no such signal'**
  String get errThisRoomHasNoSuch;

  /// No description provided for @errALotOfRoundsTime.
  ///
  /// In en, this message translates to:
  /// **'a lot of rounds — time to wrap up'**
  String get errALotOfRoundsTime;

  /// No description provided for @errZenIsForSubscribersOne.
  ///
  /// In en, this message translates to:
  /// **'zen is for subscribers: one subscription for two, and it\'s cheaper together'**
  String get errZenIsForSubscribersOne;

  /// No description provided for @errSlowDownALittle.
  ///
  /// In en, this message translates to:
  /// **'slow down a little'**
  String get errSlowDownALittle;

  /// No description provided for @errThisIsAViewingRoom.
  ///
  /// In en, this message translates to:
  /// **'this is a viewing room, not a reading room'**
  String get errThisIsAViewingRoom;

  /// No description provided for @errTheReadingHasAlreadyEnded.
  ///
  /// In en, this message translates to:
  /// **'the reading has already ended'**
  String get errTheReadingHasAlreadyEnded;

  /// No description provided for @errRightNowEveryoneReadsAt.
  ///
  /// In en, this message translates to:
  /// **'right now everyone reads at their own pace'**
  String get errRightNowEveryoneReadsAt;

  /// No description provided for @errAReadyCheckExistsOnly.
  ///
  /// In en, this message translates to:
  /// **'a ready check exists only in games'**
  String get errAReadyCheckExistsOnly;

  /// No description provided for @errTheGameHasAlreadyEnded.
  ///
  /// In en, this message translates to:
  /// **'the game has already ended'**
  String get errTheGameHasAlreadyEnded;

  /// No description provided for @errTheAlbumIsOnlyFor.
  ///
  /// In en, this message translates to:
  /// **'the album is only for a pair'**
  String get errTheAlbumIsOnlyFor;

  /// No description provided for @errThisEveningHasAlreadyPassed.
  ///
  /// In en, this message translates to:
  /// **'this evening has already passed'**
  String get errThisEveningHasAlreadyPassed;

  /// No description provided for @errTooManyUnopenedNotesWatch.
  ///
  /// In en, this message translates to:
  /// **'too many unopened notes — watch something together first'**
  String get errTooManyUnopenedNotesWatch;

  /// No description provided for @errCouldnTSaveTheQuote.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t save the quote — try again'**
  String get errCouldnTSaveTheQuote;

  /// No description provided for @errTheViewingHasnTStarted.
  ///
  /// In en, this message translates to:
  /// **'the viewing hasn\'t started yet'**
  String get errTheViewingHasnTStarted;

  /// No description provided for @errOnlyWhoeverOpenedTheRoom.
  ///
  /// In en, this message translates to:
  /// **'only whoever opened the room can close it'**
  String get errOnlyWhoeverOpenedTheRoom;

  /// No description provided for @errUserNotFound.
  ///
  /// In en, this message translates to:
  /// **'user not found'**
  String get errUserNotFound;

  /// No description provided for @errThisPersonIsAlreadyIn.
  ///
  /// In en, this message translates to:
  /// **'this person is already in your circle'**
  String get errThisPersonIsAlreadyIn;

  /// No description provided for @errYouCanOnlyInviteFriends.
  ///
  /// In en, this message translates to:
  /// **'you can only invite friends'**
  String get errYouCanOnlyInviteFriends;

  /// No description provided for @errThisPersonCanTJoin.
  ///
  /// In en, this message translates to:
  /// **'this person can\'t join this room'**
  String get errThisPersonCanTJoin;

  /// No description provided for @errThisPersonDeclinedTheInvitation.
  ///
  /// In en, this message translates to:
  /// **'this person declined the invitation'**
  String get errThisPersonDeclinedTheInvitation;

  /// No description provided for @errEnoughGuestsAlreadyNoMore.
  ///
  /// In en, this message translates to:
  /// **'enough guests already — no more seats'**
  String get errEnoughGuestsAlreadyNoMore;

  /// No description provided for @errVoiceIsnTSetUp.
  ///
  /// In en, this message translates to:
  /// **'voice isn\'t set up on this server'**
  String get errVoiceIsnTSetUp;

  /// No description provided for @errTheAnniversaryIsPartOf.
  ///
  /// In en, this message translates to:
  /// **'the anniversary is part of the pair\'s album — it unlocks with a subscription for two'**
  String get errTheAnniversaryIsPartOf;

  /// No description provided for @errTheFreeNotesHaveRun.
  ///
  /// In en, this message translates to:
  /// **'the free notes have run out — with a subscription for two you can leave them without counting'**
  String get errTheFreeNotesHaveRun;

  /// No description provided for @errTheFreeCapsuleIsAlready.
  ///
  /// In en, this message translates to:
  /// **'the free capsule is already sealed — new capsules unlock with a subscription for two'**
  String get errTheFreeCapsuleIsAlready;

  /// No description provided for @errUnknownBadge.
  ///
  /// In en, this message translates to:
  /// **'unknown badge'**
  String get errUnknownBadge;

  /// No description provided for @errThisEveningHasPassedPlan.
  ///
  /// In en, this message translates to:
  /// **'this evening has passed — plan it again to leave a note'**
  String get errThisEveningHasPassedPlan;

  /// No description provided for @errCouldnTSaveTheNote.
  ///
  /// In en, this message translates to:
  /// **'couldn\'t save the note — try again'**
  String get errCouldnTSaveTheNote;

  /// No description provided for @errTheNoteIsAlreadyOpen.
  ///
  /// In en, this message translates to:
  /// **'the note is already open — it can\'t be removed'**
  String get errTheNoteIsAlreadyOpen;

  /// No description provided for @errTheNoteIsStillSealed.
  ///
  /// In en, this message translates to:
  /// **'the note is still sealed'**
  String get errTheNoteIsStillSealed;

  /// No description provided for @errUnknownReaction.
  ///
  /// In en, this message translates to:
  /// **'unknown reaction'**
  String get errUnknownReaction;

  /// No description provided for @errTheCapsuleHasAlreadyOpened.
  ///
  /// In en, this message translates to:
  /// **'the capsule has already opened — the letter didn\'t make it in'**
  String get errTheCapsuleHasAlreadyOpened;

  /// No description provided for @errYourLetterIsAlreadySealed.
  ///
  /// In en, this message translates to:
  /// **'your letter is already sealed in this capsule'**
  String get errYourLetterIsAlreadySealed;

  /// No description provided for @errItSTooEarlyThe.
  ///
  /// In en, this message translates to:
  /// **'it\'s too early — the capsule opens later'**
  String get errItSTooEarlyThe;

  /// No description provided for @errOnlyWhoeverSealedTheCapsule.
  ///
  /// In en, this message translates to:
  /// **'only whoever sealed the capsule can remove it'**
  String get errOnlyWhoeverSealedTheCapsule;

  /// No description provided for @errTheCapsuleHasAlreadyOpened2.
  ///
  /// In en, this message translates to:
  /// **'the capsule has already opened'**
  String get errTheCapsuleHasAlreadyOpened2;

  /// No description provided for @errYourPartnerSLetterIs.
  ///
  /// In en, this message translates to:
  /// **'your partner\'s letter is already in the capsule — it can\'t be removed'**
  String get errYourPartnerSLetterIs;

  /// No description provided for @errPromoCodeNotFound.
  ///
  /// In en, this message translates to:
  /// **'promo code not found'**
  String get errPromoCodeNotFound;

  /// No description provided for @errYouCanTUseYour.
  ///
  /// In en, this message translates to:
  /// **'you can\'t use your own promo code'**
  String get errYouCanTUseYour;

  /// No description provided for @errThisPromoCodeHasAlready.
  ///
  /// In en, this message translates to:
  /// **'this promo code has already been used'**
  String get errThisPromoCodeHasAlready;

  /// No description provided for @errThePromoDiscountOnlyApplies.
  ///
  /// In en, this message translates to:
  /// **'the promo discount only applies to a first purchase'**
  String get errThePromoDiscountOnlyApplies;

  /// No description provided for @errThisPromoCodeIsnT.
  ///
  /// In en, this message translates to:
  /// **'this promo code isn\'t available for this account'**
  String get errThisPromoCodeIsnT;

  /// No description provided for @errTheTrialIsNoLonger.
  ///
  /// In en, this message translates to:
  /// **'the trial is no longer available for this account'**
  String get errTheTrialIsNoLonger;

  /// No description provided for @errEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'empty message'**
  String get errEmptyMessage;

  /// No description provided for @errEmptyNote.
  ///
  /// In en, this message translates to:
  /// **'empty note'**
  String get errEmptyNote;

  /// No description provided for @errSomeoneIsReadingAloudRight.
  ///
  /// In en, this message translates to:
  /// **'someone is reading aloud right now'**
  String get errSomeoneIsReadingAloudRight;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/booth_models.dart';

class PhotoBoothConfig extends ChangeNotifier {
  BoothFilter filter = BoothFilter.none;
  BoothFrameOption frame = kFrameOptions.first;
  double cropScale = 1.0;
  double cropOffsetX = 0.0;
  double cropOffsetY = 0.0;
  double cropTopPercent = 0.0;
  double cropBottomPercent = 0.0;
  double cropLeftPercent = 0.0;
  double cropRightPercent = 0.0;
  double cameraZoomLevel = 1.0;
  bool showGrid = true;
  BoothFlipMode flipMode = BoothFlipMode.livePreviewOnly;
  BoothAspectRatio aspectRatio = BoothAspectRatio.auto;
  int countdownSeconds = 3;
  int? photoCountOverride;
  ResolutionPreset resolutionPreset = ResolutionPreset.high;
  String? preferredCameraId;
  String? preferredCameraName;
  bool enableImageCompression = true;
  BoothCompressionProfile imageCompressionProfile =
      BoothCompressionProfile.high;
  bool enablePhotostripSharpening = false;
  bool enableLivePhotoCompression = true;
  BoothCompressionProfile movingStripCompressionProfile =
      BoothCompressionProfile.high;
  BoothScreenOrientation screenOrientation = BoothScreenOrientation.landscape;
  bool showCropPreviewInLiveView = true;
  BoothShutterSpeed shutterSpeed = BoothShutterSpeed.q1_60;
  BoothWhiteBalancePreset whiteBalancePreset = BoothWhiteBalancePreset.auto;
  BoothIsoSetting isoSetting = BoothIsoSetting.iso12800;
  BoothApertureSetting apertureSetting = BoothApertureSetting.f11;
  bool enableExternalFlash = false;
  bool disableAllPrinting = false;
  String primaryPrinter = 'DS-RX1 (Default)';
  bool enableSecondaryPrinter = false;
  String? secondaryPrinter;
  BoothPrintMode printMode = BoothPrintMode.individualPrints;
  double printScalePercent = 100.0;
  double printHorizontalOffset = 0.0;
  double printVerticalOffset = 0.0;
  bool enable2Rto4RConversion = false;
  int firstPhotoCountdownSeconds = 5;
  bool disablePreviewCountdownTimer = false;
  int previewCountdownSeconds = 5;
  int nextPhotoCountdownSeconds = 5;
  int outputResultPageCountdownSeconds = 60;
  int sessionTimerMinutes = 5;
  bool enableGlobalCountdownTimerSession = false;
  bool enableRetakeButton = true;
  bool unlimitedRetakes = false;
  int retakeLimitPerPhoto = 5;
  bool enableTapToStartOverlayScreen = true;
  bool enablePayment = false;
  int paymentAmountIdr = 35000;
  String paymentGateway = 'Midtrans (Default)';
  String voucherAmountMode = 'Use 0 (Free)';
  String paymentMethodVisibility = 'Show Both (QRIS & Voucher)';
  String midtransEnvironment = 'Production';
  bool showPaymentKeys = false;
  String midtransServerKey = '';
  String midtransClientKey = '';
  String merchantToken = '';
  bool enableMultiPrintFunctionality = true;
  int maxPrintQuantity = 5;
  bool enableMultiplePrintDiscount = false;
  int discountThresholdPrints = 2;
  int discountPercentage = 10;
  int maximumPrintsForDiscount = 10;
  bool enableExtraPrint = true;
  int extraPrintPriceIdr = 5000;
  int extraPrintDiscountPercentage = 10;
  int extraPrintDiscountThreshold = 3;
  int maximumExtraPrints = 10;
  bool enableExtraPrintPayment = false;
  String boothName = 'VARGOBOOTH';
  String boothTagline = 'learn fun with me';
  String adminPin = '1234';
  String? customLogoPath;
  String language = 'English';
  bool autoPrintOnOutputPage = false;
  bool enableEmailOnOutputPage = false;
  bool enableConsentForm = false;
  bool enableMovingStripMode = true;
  bool skipPhotostripCreation = false;
  bool enablePhotoZoomPan = false;
  bool autoSelectSingleFrame = false;
  bool skipFilterSelection = false;
  String movingStripPerformanceMode = 'Auto (Detect PC specs)';
  String movingStripLoopCount = '2 Loops (~10s) - Default';
  String activationCode = 'f3b44331-5bf8-410c-9f1f-10d5235f2708';
  double logoSizePx = 800.0;
  bool enablePrintButton = true;
  bool uploadOriginalPhotosToLuminashDrive = true;
  bool autoSyncFramesOnStartup = true;
  bool showPhotoCountModal = false;
  bool enableRemoteSettingsSync = false;
  bool enableReprintLogging = false;
  int reprintAmountIdr = 0;
  String licenseExpiryText = '4/19/2026, 9:17:30 AM';
  String licenseVersion = 'ultimate';
  int licenseMaxDevices = 1;
  List<String> licenseUsedDevices = <String>[
    'DESKTOP-8CD6I4F_bb6d7cbff97468d493a13f47e57489ff',
  ];
  String appearanceMainBackgroundHex = '#CCCCCC';
  String appearanceMainTextHex = '#171717';
  String appearancePrimary1BackgroundHex = '#CFC3AF';
  String appearancePrimary1TextHex = '#212121';
  String appearancePrimary2BackgroundHex = '#212121';
  String appearancePrimary2TextHex = '#CFC3AF';
  String appearanceButton1BackgroundHex = '#383838';
  String appearanceButton1TextHex = '#EDEDED';
  String appearanceButton2BackgroundHex = '#5EB06F';
  String appearanceButton2TextHex = '#242424';
  String appearanceButton3BackgroundHex = '#2D77B4';
  String appearanceButton3TextHex = '#EDEDED';
  String appearanceFontFamily = 'Josefin Sans (Default)';
  String? customBackgroundPath;
  String? customFontPath;
  String? customHomePagePath;
  String? customTutorialPath;
  String? customLoadingMediaPath;

  bool get mirrorPreview => flipMode.mirrorsPreview;

  void setFilter(BoothFilter value) {
    filter = value;
    notifyListeners();
  }

  void setFrame(BoothFrameOption value) {
    frame = value;
    notifyListeners();
  }

  void setCropScale(double value) {
    cropScale = value;
    notifyListeners();
  }

  void setCropOffsetX(double value) {
    cropOffsetX = value;
    notifyListeners();
  }

  void setCropOffsetY(double value) {
    cropOffsetY = value;
    notifyListeners();
  }

  void setShowGrid(bool value) {
    showGrid = value;
    notifyListeners();
  }

  void setMirrorPreview(bool value) {
    flipMode = value ? BoothFlipMode.livePreviewOnly : BoothFlipMode.none;
    notifyListeners();
  }

  void setFlipMode(BoothFlipMode value) {
    flipMode = value;
    notifyListeners();
  }

  void setAspectRatio(BoothAspectRatio value) {
    aspectRatio = value;
    notifyListeners();
  }

  void setCountdownSeconds(int value) {
    countdownSeconds = value;
    notifyListeners();
  }

  void setPhotoCountOverride(int? value) {
    photoCountOverride = value;
    notifyListeners();
  }

  void setResolutionPreset(ResolutionPreset value) {
    resolutionPreset = value;
    notifyListeners();
  }

  void setPreferredCamera({required String id, required String name}) {
    preferredCameraId = id;
    preferredCameraName = name;
    notifyListeners();
  }

  void setEnableImageCompression(bool value) {
    enableImageCompression = value;
    notifyListeners();
  }

  void setImageCompressionProfile(BoothCompressionProfile value) {
    imageCompressionProfile = value;
    notifyListeners();
  }

  void setEnablePhotostripSharpening(bool value) {
    enablePhotostripSharpening = value;
    notifyListeners();
  }

  void setEnableLivePhotoCompression(bool value) {
    enableLivePhotoCompression = value;
    notifyListeners();
  }

  void setMovingStripCompressionProfile(BoothCompressionProfile value) {
    movingStripCompressionProfile = value;
    notifyListeners();
  }

  void setScreenOrientation(BoothScreenOrientation value) {
    screenOrientation = value;
    notifyListeners();
  }

  void setShowCropPreviewInLiveView(bool value) {
    showCropPreviewInLiveView = value;
    notifyListeners();
  }

  void setShutterSpeed(BoothShutterSpeed value) {
    shutterSpeed = value;
    notifyListeners();
  }

  void setWhiteBalancePreset(BoothWhiteBalancePreset value) {
    whiteBalancePreset = value;
    notifyListeners();
  }

  void setIsoSetting(BoothIsoSetting value) {
    isoSetting = value;
    notifyListeners();
  }

  void setApertureSetting(BoothApertureSetting value) {
    apertureSetting = value;
    notifyListeners();
  }

  void setEnableExternalFlash(bool value) {
    enableExternalFlash = value;
    notifyListeners();
  }

  void setCameraZoomLevel(double value) {
    cameraZoomLevel = value.clamp(1.0, 8.0);
    notifyListeners();
  }

  void setDisableAllPrinting(bool value) {
    disableAllPrinting = value;
    notifyListeners();
  }

  void setPrimaryPrinter(String value) {
    primaryPrinter = value;
    notifyListeners();
  }

  void setEnableSecondaryPrinter(bool value) {
    enableSecondaryPrinter = value;
    notifyListeners();
  }

  void setSecondaryPrinter(String? value) {
    secondaryPrinter = value;
    notifyListeners();
  }

  void setPrintMode(BoothPrintMode value) {
    printMode = value;
    notifyListeners();
  }

  void setPrintScalePercent(double value) {
    printScalePercent = value.clamp(50.0, 100.0);
    notifyListeners();
  }

  void setPrintHorizontalOffset(double value) {
    printHorizontalOffset = value.clamp(-50.0, 50.0);
    notifyListeners();
  }

  void setPrintVerticalOffset(double value) {
    printVerticalOffset = value.clamp(-50.0, 50.0);
    notifyListeners();
  }

  void setEnable2Rto4RConversion(bool value) {
    enable2Rto4RConversion = value;
    notifyListeners();
  }

  void setFirstPhotoCountdownSeconds(int value) {
    firstPhotoCountdownSeconds = value.clamp(0, 120);
    notifyListeners();
  }

  void setDisablePreviewCountdownTimer(bool value) {
    disablePreviewCountdownTimer = value;
    notifyListeners();
  }

  void setPreviewCountdownSeconds(int value) {
    previewCountdownSeconds = value.clamp(0, 120);
    notifyListeners();
  }

  void setNextPhotoCountdownSeconds(int value) {
    nextPhotoCountdownSeconds = value.clamp(0, 120);
    notifyListeners();
  }

  void setOutputResultPageCountdownSeconds(int value) {
    outputResultPageCountdownSeconds = value.clamp(0, 600);
    notifyListeners();
  }

  void setSessionTimerMinutes(int value) {
    sessionTimerMinutes = value.clamp(0, 180);
    notifyListeners();
  }

  void setEnableGlobalCountdownTimerSession(bool value) {
    enableGlobalCountdownTimerSession = value;
    notifyListeners();
  }

  void setEnableRetakeButton(bool value) {
    enableRetakeButton = value;
    notifyListeners();
  }

  void setUnlimitedRetakes(bool value) {
    unlimitedRetakes = value;
    notifyListeners();
  }

  void setRetakeLimitPerPhoto(int value) {
    retakeLimitPerPhoto = value.clamp(0, 50);
    notifyListeners();
  }

  void setEnableTapToStartOverlayScreen(bool value) {
    enableTapToStartOverlayScreen = value;
    notifyListeners();
  }

  void setEnablePayment(bool value) {
    enablePayment = value;
    notifyListeners();
  }

  void setPaymentAmountIdr(int value) {
    paymentAmountIdr = value.clamp(0, 10000000);
    notifyListeners();
  }

  void setPaymentGateway(String value) {
    paymentGateway = value;
    notifyListeners();
  }

  void setVoucherAmountMode(String value) {
    voucherAmountMode = value;
    notifyListeners();
  }

  void setPaymentMethodVisibility(String value) {
    paymentMethodVisibility = value;
    notifyListeners();
  }

  void setMidtransEnvironment(String value) {
    midtransEnvironment = value;
    notifyListeners();
  }

  void setShowPaymentKeys(bool value) {
    showPaymentKeys = value;
    notifyListeners();
  }

  void setMidtransServerKey(String value) {
    midtransServerKey = value;
    notifyListeners();
  }

  void setMidtransClientKey(String value) {
    midtransClientKey = value;
    notifyListeners();
  }

  void setMerchantToken(String value) {
    merchantToken = value;
    notifyListeners();
  }

  void setEnableMultiPrintFunctionality(bool value) {
    enableMultiPrintFunctionality = value;
    notifyListeners();
  }

  void setMaxPrintQuantity(int value) {
    maxPrintQuantity = value.clamp(1, 50);
    notifyListeners();
  }

  void setEnableMultiplePrintDiscount(bool value) {
    enableMultiplePrintDiscount = value;
    notifyListeners();
  }

  void setDiscountThresholdPrints(int value) {
    discountThresholdPrints = value.clamp(1, 50);
    notifyListeners();
  }

  void setDiscountPercentage(int value) {
    discountPercentage = value.clamp(0, 100);
    notifyListeners();
  }

  void setMaximumPrintsForDiscount(int value) {
    maximumPrintsForDiscount = value.clamp(1, 100);
    notifyListeners();
  }

  void setEnableExtraPrint(bool value) {
    enableExtraPrint = value;
    notifyListeners();
  }

  void setExtraPrintPriceIdr(int value) {
    extraPrintPriceIdr = value.clamp(0, 1000000);
    notifyListeners();
  }

  void setExtraPrintDiscountPercentage(int value) {
    extraPrintDiscountPercentage = value.clamp(0, 100);
    notifyListeners();
  }

  void setExtraPrintDiscountThreshold(int value) {
    extraPrintDiscountThreshold = value.clamp(1, 100);
    notifyListeners();
  }

  void setMaximumExtraPrints(int value) {
    maximumExtraPrints = value.clamp(1, 100);
    notifyListeners();
  }

  void setEnableExtraPrintPayment(bool value) {
    enableExtraPrintPayment = value;
    notifyListeners();
  }

  void setBoothName(String value) {
    boothName = value;
    notifyListeners();
  }

  void setBoothTagline(String value) {
    boothTagline = value;
    notifyListeners();
  }

  void setAdminPin(String value) {
    adminPin = value;
    notifyListeners();
  }

  void setCustomLogoPath(String? value) {
    customLogoPath = value;
    notifyListeners();
  }

  void setLanguage(String value) {
    language = value;
    notifyListeners();
  }

  void setAutoPrintOnOutputPage(bool value) {
    autoPrintOnOutputPage = value;
    notifyListeners();
  }

  void setEnableEmailOnOutputPage(bool value) {
    enableEmailOnOutputPage = value;
    notifyListeners();
  }

  void setEnableConsentForm(bool value) {
    enableConsentForm = value;
    notifyListeners();
  }

  void setEnableMovingStripMode(bool value) {
    enableMovingStripMode = value;
    notifyListeners();
  }

  void setSkipPhotostripCreation(bool value) {
    skipPhotostripCreation = value;
    notifyListeners();
  }

  void setEnablePhotoZoomPan(bool value) {
    enablePhotoZoomPan = value;
    notifyListeners();
  }

  void setAutoSelectSingleFrame(bool value) {
    autoSelectSingleFrame = value;
    notifyListeners();
  }

  void setSkipFilterSelection(bool value) {
    skipFilterSelection = value;
    notifyListeners();
  }

  void setMovingStripPerformanceMode(String value) {
    movingStripPerformanceMode = value;
    notifyListeners();
  }

  void setMovingStripLoopCount(String value) {
    movingStripLoopCount = value;
    notifyListeners();
  }

  void setActivationCode(String value) {
    activationCode = value;
    notifyListeners();
  }

  void setLogoSizePx(double value) {
    logoSizePx = value.clamp(300.0, 1800.0);
    notifyListeners();
  }

  void setEnablePrintButton(bool value) {
    enablePrintButton = value;
    notifyListeners();
  }

  void setUploadOriginalPhotosToLuminashDrive(bool value) {
    uploadOriginalPhotosToLuminashDrive = value;
    notifyListeners();
  }

  void setAutoSyncFramesOnStartup(bool value) {
    autoSyncFramesOnStartup = value;
    notifyListeners();
  }

  void setShowPhotoCountModal(bool value) {
    showPhotoCountModal = value;
    notifyListeners();
  }

  void setEnableRemoteSettingsSync(bool value) {
    enableRemoteSettingsSync = value;
    notifyListeners();
  }

  void setEnableReprintLogging(bool value) {
    enableReprintLogging = value;
    notifyListeners();
  }

  void setReprintAmountIdr(int value) {
    reprintAmountIdr = value.clamp(0, 1000000);
    notifyListeners();
  }

  void setLicenseExpiryText(String value) {
    licenseExpiryText = value;
    notifyListeners();
  }

  void setLicenseVersion(String value) {
    licenseVersion = value;
    notifyListeners();
  }

  void setLicenseMaxDevices(int value) {
    licenseMaxDevices = value.clamp(1, 100);
    notifyListeners();
  }

  void setLicenseUsedDevices(List<String> value) {
    licenseUsedDevices = List<String>.from(value);
    notifyListeners();
  }

  void setAppearanceMainBackgroundHex(String value) {
    appearanceMainBackgroundHex = value;
    notifyListeners();
  }

  void setAppearanceMainTextHex(String value) {
    appearanceMainTextHex = value;
    notifyListeners();
  }

  void setAppearancePrimary1BackgroundHex(String value) {
    appearancePrimary1BackgroundHex = value;
    notifyListeners();
  }

  void setAppearancePrimary1TextHex(String value) {
    appearancePrimary1TextHex = value;
    notifyListeners();
  }

  void setAppearancePrimary2BackgroundHex(String value) {
    appearancePrimary2BackgroundHex = value;
    notifyListeners();
  }

  void setAppearancePrimary2TextHex(String value) {
    appearancePrimary2TextHex = value;
    notifyListeners();
  }

  void setAppearanceButton1BackgroundHex(String value) {
    appearanceButton1BackgroundHex = value;
    notifyListeners();
  }

  void setAppearanceButton1TextHex(String value) {
    appearanceButton1TextHex = value;
    notifyListeners();
  }

  void setAppearanceButton2BackgroundHex(String value) {
    appearanceButton2BackgroundHex = value;
    notifyListeners();
  }

  void setAppearanceButton2TextHex(String value) {
    appearanceButton2TextHex = value;
    notifyListeners();
  }

  void setAppearanceButton3BackgroundHex(String value) {
    appearanceButton3BackgroundHex = value;
    notifyListeners();
  }

  void setAppearanceButton3TextHex(String value) {
    appearanceButton3TextHex = value;
    notifyListeners();
  }

  void setAppearanceFontFamily(String value) {
    appearanceFontFamily = value;
    notifyListeners();
  }

  void setCustomBackgroundPath(String? value) {
    customBackgroundPath = value;
    notifyListeners();
  }

  void setCustomFontPath(String? value) {
    customFontPath = value;
    notifyListeners();
  }

  void setCustomHomePagePath(String? value) {
    customHomePagePath = value;
    notifyListeners();
  }

  void setCustomTutorialPath(String? value) {
    customTutorialPath = value;
    notifyListeners();
  }

  void setCustomLoadingMediaPath(String? value) {
    customLoadingMediaPath = value;
    notifyListeners();
  }

  void setCropTopPercent(double value) {
    cropTopPercent = value.clamp(0.0, 0.45);
    notifyListeners();
  }

  void setCropBottomPercent(double value) {
    cropBottomPercent = value.clamp(0.0, 0.45);
    notifyListeners();
  }

  void setCropLeftPercent(double value) {
    cropLeftPercent = value.clamp(0.0, 0.45);
    notifyListeners();
  }

  void setCropRightPercent(double value) {
    cropRightPercent = value.clamp(0.0, 0.45);
    notifyListeners();
  }
}

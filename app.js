// ─────────────────────────────────────────────────────────────
//  APPLICATION MODE STATE
// ─────────────────────────────────────────────────────────────
let appMode = null; // 'studio' | 'event'

// Event Kiosk Mode State
let eventQueue       = [];      // {id, imageData, timestamp, editParams, status}
let evtPollTimer     = null;    // setInterval handle for queue polling
let evtLocalUrl      = '';      // http://192.168.x.x:8080/customer
let evtQRInstance    = null;    // qrcode.js instance
let evtSessionPrinted = 0;      // counter for this session
let evtTemplateImage  = null;   // PNG overlay for event mode
let evtActiveChannel  = '6x4';  // paper channel for event mode

// ─────────────────────────────────────────────────────────────
//  GLOBAL STATE VARIABLES (Studio Pro mode)
// ─────────────────────────────────────────────────────────────
let inputDirHandle = null;

let archiveDirHandle = null;
let filesQueue = [];
let templateImage = null;
let templateFileName = '';
let isProcessing = false;
let pauseRequested = false;
let currentIndex = 0;
let batchStartTime = null;

// Sizing & Paper Channels state
let activeChannel = '6x4'; // Default channel

const paperChannels = {
  '6x4': { name: '6x4', w: 6, h: 4, ratio: 1.5 },
  '6x8': { name: '6x8', w: 6, h: 8, ratio: 0.75 },
  '6x9': { name: '6x9', w: 6, h: 9, ratio: 0.6667 },
  '6x12': { name: '6x12', w: 6, h: 12, ratio: 0.5 },
  '5x7': { name: '5x7', w: 5, h: 7, ratio: 0.7143 },
  '8x10': { name: '8x10', w: 8, h: 10, ratio: 0.8 },
  '8x12': { name: '8x12', w: 8, h: 12, ratio: 0.6667 }
};

// Layout and View mode state
let viewMode = 'grid'; // 'grid' or 'detail'
let gridPage = 0;
let activeItem = null; // Item selected for editing/detail zoom

// Split screen slider state
let splitPercent = 0.5;
let isDraggingSlider = false;

// Caches for preview rendering
let originalPreviewImg = null; 
let originalPreviewCanvas = null; 
let processedPreviewCanvas = null; 

// Interactive Crop state
let cropActive = false;
let isDraggingCrop = false;
let cropDragType = null; // 'move' or handle name e.g. 'nw'
let cropStartMouse = { x: 0, y: 0 };
let cropStartBox = { x: 0, y: 0, w: 0, h: 0 };

// Folder & Selection State
let hotFolderPath = localStorage.getItem('gs_hot_folder') || 'C:\\Fujifilm_Hotfolder';
let outputFolderPath = localStorage.getItem('gs_output_folder') || 'Printed_Photos';
let sourceFolderPath = '';
let lastSelectedExplorerIndex = -1;
let currentPrintDestination = localStorage.getItem('gs_print_destination') || 'hotfolder';
let fbTarget = 'hotfolder';
let fbCurrentPath = 'C:\\Fujifilm_Hotfolder';

// Auto Mode, Sensitivity Percentages & Zoom State
let isAutoMode = localStorage.getItem('gs_auto_mode') === 'true';
let colorStepPct = parseFloat(localStorage.getItem('gs_color_step_pct')) || 2.5;
let densityStepPct = parseFloat(localStorage.getItem('gs_density_step_pct')) || 2.5;
let is1to1Zoom = false;

// UI Elements mapping
const els = {
  // Print Destination Toggle
  btnDestHotfolder: document.getElementById('btnDestHotfolder'),
  btnDestDirect: document.getElementById('btnDestDirect'),
  printDestDescription: document.getElementById('printDestDescription'),
  hotFolderRowGroup: document.getElementById('hotFolderRowGroup'),

  // Hot Foil & Output Directory Selectors
  btnSelectHotFolder: document.getElementById('btnSelectHotFolder'),
  hotFolderPathDisplay: document.getElementById('hotFolderPathDisplay'),
  hotFolderStatus: document.getElementById('hotFolderStatus'),
  btnSelectOutput: document.getElementById('btnSelectOutput'),
  outputPathDisplay: document.getElementById('outputPathDisplay'),
  btnSelectArchive: document.getElementById('btnSelectArchive'),
  archivePathDisplay: document.getElementById('archivePathDisplay'),

  // In-Software Folder Browser Modal
  folderBrowserModal: document.getElementById('folderBrowserModal'),
  btnCloseFolderBrowserModal: document.getElementById('btnCloseFolderBrowserModal'),
  fbModalTitle: document.getElementById('fbModalTitle'),
  fbTargetName: document.getElementById('fbTargetName'),
  fbPathInput: document.getElementById('fbPathInput'),
  fbBtnGo: document.getElementById('fbBtnGo'),
  fbBtnUp: document.getElementById('fbBtnUp'),
  fbDrivesContainer: document.getElementById('fbDrivesContainer'),
  fbDirList: document.getElementById('fbDirList'),
  fbSelectedPathPreview: document.getElementById('fbSelectedPathPreview'),
  fbBtnNewFolder: document.getElementById('fbBtnNewFolder'),
  fbBtnCancel: document.getElementById('fbBtnCancel'),
  fbBtnSelect: document.getElementById('fbBtnSelect'),
  
  // Dynamic Source Photos & Windows File Management
  btnSelectSourceFolder: document.getElementById('btnSelectSourceFolder'),
  sourceCountBadge: document.getElementById('sourceCountBadge'),
  sourcePathDisplay: document.getElementById('sourcePathDisplay'),
  sourceSelectionBar: document.getElementById('sourceSelectionBar'),
  btnSelectAll: document.getElementById('btnSelectAll'),
  btnDeselectAll: document.getElementById('btnDeselectAll'),
  selectedCountDisplay: document.getElementById('selectedCountDisplay'),
  sourceSearchInput: document.getElementById('sourceSearchInput'),
  sourceFileList: document.getElementById('sourceFileList'),
  
  // Paper Channel Selector
  paperChannelSelect: document.getElementById('paperChannelSelect'),
  
  // File selection
  btnBrowseFiles: document.getElementById('btnBrowseFiles'),
  btnClearQueue: document.getElementById('btnClearQueue'),
  fileSelector: document.getElementById('fileSelector'),
  sourceDirInput: document.getElementById('sourceDirInput'),
  inputPathDisplay: document.getElementById('inputPathDisplay'),
  
  // Template upload
  templateInput: document.getElementById('templateInput'),
  templatePreviewBlock: document.getElementById('templatePreviewBlock'),
  templateThumbnail: document.getElementById('templateThumbnail'),
  templateName: document.getElementById('templateName'),
  btnRemoveTemplate: document.getElementById('btnRemoveTemplate'),
  
  // Watermark parameters
  templateOpacity: document.getElementById('templateOpacity'),
  opacityValue: document.getElementById('opacityValue'),
  templateScale: document.getElementById('templateScale'),
  scaleValue: document.getElementById('scaleValue'),
  templatePosition: document.getElementById('templatePosition'),
  templateMargin: document.getElementById('templateMargin'),
  marginValue: document.getElementById('marginValue'),
  
  // Sidebar Color Controls
  chkColorCorrection: document.getElementById('chkColorCorrection'),
  correctionAlgorithm: document.getElementById('correctionAlgorithm'),
  colorCorrectionParams: document.getElementById('colorCorrectionParams'),
  activeEditBadge: document.getElementById('activeEditBadge'),
  
  // Noritsu C, M, Y, D Buttons
  btnResetSidebarCMYD: document.getElementById('btnResetSidebarCMYD'),
  btnCUp: document.getElementById('btnCUp'),
  btnCDown: document.getElementById('btnCDown'),
  valC: document.getElementById('valC'),
  
  btnMUp: document.getElementById('btnMUp'),
  btnMDown: document.getElementById('btnMDown'),
  valM: document.getElementById('valM'),
  
  btnYUp: document.getElementById('btnYUp'),
  btnYDown: document.getElementById('btnYDown'),
  valY: document.getElementById('valY'),
  
  btnDUp: document.getElementById('btnDUp'),
  btnDDown: document.getElementById('btnDDown'),
  valD: document.getElementById('valD'),
  
  paramContrast: document.getElementById('paramContrast'),
  contrastValue: document.getElementById('contrastValue'),
  paramSaturation: document.getElementById('paramSaturation'),
  saturationValue: document.getElementById('saturationValue'),
  
  // View mode containers
  gridModeContainer: document.getElementById('gridModeContainer'),
  detailModeContainer: document.getElementById('detailModeContainer'),
  btnToggleViewMode: document.getElementById('btnToggleViewMode'),
  
  // Grid mode UI elements
  btnPrevPage: document.getElementById('btnPrevPage'),
  btnNextPage: document.getElementById('btnNextPage'),
  gridPageIndicator: document.getElementById('gridPageIndicator'),
  btnPrintPageAll: document.getElementById('btnPrintPageAll'),
  
  // Detail mode UI elements
  btnBackToGrid: document.getElementById('btnBackToGrid'),
  detailFilenameDisplay: document.getElementById('detailFilenameDisplay'),
  btnToggleCropTool: document.getElementById('btnToggleCropTool'),
  btnResetCrop: document.getElementById('btnResetCrop'),
  btnPrintDetail: document.getElementById('btnPrintDetail'),
  
  btnDetailModeCut: document.getElementById('btnDetailModeCut'),
  btnDetailModeOverall: document.getElementById('btnDetailModeOverall'),
  
  // Classic/detail canvas & slider
  previewCanvas: document.getElementById('previewCanvas'),
  previewViewport: document.getElementById('previewViewport'),
  canvasWrapper: document.getElementById('canvasWrapper'),
  comparisonSliderBar: document.getElementById('comparisonSliderBar'),
  comparisonSliderHandle: document.getElementById('comparisonSliderHandle'),
  previewRightLabel: document.getElementById('previewRightLabel'),
  
  // Crop UI
  cropOverlay: document.getElementById('cropOverlay'),
  cropBox: document.getElementById('cropBox'),
  
  // Queue list panel (right sidebar - removed in HTML, checked for null in script)
  queueCount: document.getElementById('queueCount'),
  queueSelectionBar: document.getElementById('queueSelectionBar'),
  queueSearch: document.getElementById('queueSearch'),
  queueList: document.getElementById('queueList'),
  
  // Progress/Process logs
  processHeaderTitle: document.getElementById('processHeaderTitle'),
  processProgressStats: document.getElementById('processProgressStats'),
  progressBarFill: document.getElementById('progressBarFill'),
  etaContainer: document.getElementById('etaContainer'),
  btnStartProcess: document.getElementById('btnStartProcess'),
  btnPauseProcess: document.getElementById('btnPauseProcess'),
  logPanel: document.getElementById('logPanel'),
  toastContainer: document.getElementById('toastContainer'),

  // Auto Mode & Settings
  chkAutoMode: document.getElementById('chkAutoMode'),
  btnOpenSettings: document.getElementById('btnOpenSettings'),
  btnQuickSettings: document.getElementById('btnQuickSettings'),
  settingsModal: document.getElementById('settingsModal'),
  btnCloseSettingsModal: document.getElementById('btnCloseSettingsModal'),
  btnCancelSettings: document.getElementById('btnCancelSettings'),
  btnSaveSettings: document.getElementById('btnSaveSettings'),
  settingColorStep: document.getElementById('settingColorStep'),
  colorStepValDisplay: document.getElementById('colorStepValDisplay'),
  settingDensityStep: document.getElementById('settingDensityStep'),
  densityStepValDisplay: document.getElementById('densityStepValDisplay'),
  sidebarColorPctDisplay: document.getElementById('sidebarColorPctDisplay'),
  sidebarDensityPctDisplay: document.getElementById('sidebarDensityPctDisplay'),
  modalHotFolderDisplay: document.getElementById('modalHotFolderDisplay'),
  modalOutputDisplay: document.getElementById('modalOutputDisplay'),
  btnModalSelectHotFolder: document.getElementById('btnModalSelectHotFolder'),
  btnModalSelectOutput: document.getElementById('btnModalSelectOutput'),

  // 1:1 Magnification & Single-Frame Context Menu
  btnZoom1to1: document.getElementById('btnZoom1to1'),
  singleFrameContextMenu: document.getElementById('singleFrameContextMenu'),
  ctxCropBtn: document.getElementById('ctxCropBtn'),
  ctxZoomBtn: document.getElementById('ctxZoomBtn'),
  ctxResetCropBtn: document.getElementById('ctxResetCropBtn'),
  ctxBackBtn: document.getElementById('ctxBackBtn'),

  // Wi-Fi Camera Tool & Ingest
  btnOpenSplashCameraTool: document.getElementById('btnOpenSplashCameraTool'),
  btnSplashOpenCamModal: document.getElementById('btnSplashOpenCamModal'),
  splashCameraPill: document.getElementById('splashCameraPill'),
  cameraSetupModal: document.getElementById('cameraSetupModal'),
  btnCloseCameraModal: document.getElementById('btnCloseCameraModal'),
  btnCamModalCancel: document.getElementById('btnCamModalCancel'),
  btnLaunchStudioFromCameraModal: document.getElementById('btnLaunchStudioFromCameraModal'),
  camServerStatusIndicator: document.getElementById('camServerStatusIndicator'),
  camServerStatusText: document.getElementById('camServerStatusText'),
  btnToggleCameraServer: document.getElementById('btnToggleCameraServer'),
  camHostIpDisplay: document.getElementById('camHostIpDisplay'),
  btnCopyCamIp: document.getElementById('btnCopyCamIp'),
  camHotspotBanner: document.getElementById('camHotspotBanner'),
  camTargetFolderDisplay: document.getElementById('camTargetFolderDisplay'),
  btnChangeCamTargetFolder: document.getElementById('btnChangeCamTargetFolder'),
  camTotalShotsBadge: document.getElementById('camTotalShotsBadge'),
  camRecentArrivalsList: document.getElementById('camRecentArrivalsList'),
  camEmptyFeedMsg: document.getElementById('camEmptyFeedMsg'),
  cameraIngestBar: document.getElementById('cameraIngestBar'),
  cameraLivePill: document.getElementById('cameraLivePill'),
  chkCameraAutoIngest: document.getElementById('chkCameraAutoIngest'),
  btnOpenStudioCameraSettings: document.getElementById('btnOpenStudioCameraSettings')
};

// Default Image Parameters Generator
function getDefaultEditParams() {
  return {
    chkColorCorrection: true,
    correctionAlgorithm: 'both',
    paramC: 0,
    paramM: 0,
    paramY: 0,
    paramD: 0,
    paramSPD: 0,
    paramContrast: 0,
    paramSaturation: 0
  };
}

// Return channel dimensions oriented to print channel
// If image is portrait (imgW < imgH), width is short side (4") and height is long side (6")
// If image is landscape (imgW >= imgH), width is long side (6") and height is short side (4")
function getOrientedChannelDims(imgW, imgH, channelKey) {
  const channel = paperChannels[channelKey] || paperChannels['6x4'];
  const channelLong = Math.max(channel.w, channel.h);
  const channelShort = Math.min(channel.w, channel.h);
  if (imgW && imgH && imgW < imgH) {
    return { w: channelShort, h: channelLong };
  }
  return { w: channelLong, h: channelShort };
}

// Get channel aspect ratio based on image orientation
// If image is portrait (imgW < imgH), ratio is short side / long side (e.g. 4/6 = 0.6667 for 6x4)
// If image is landscape (imgW >= imgH), ratio is long side / short side (e.g. 6/4 = 1.5 for 6x4)
function getChannelRatio(imgW, imgH, channelKey) {
  const channel = paperChannels[channelKey] || paperChannels['6x4'];
  const channelLong = Math.max(channel.w, channel.h);
  const channelShort = Math.min(channel.w, channel.h);
  if (imgW && imgH && imgW < imgH) {
    return channelShort / channelLong;
  }
  return channelLong / channelShort;
}

// Return a canvas with the image rotated (if needed) so its orientation matches the channel.
// The long side of the image is aligned with the long (6-inch) side of the channel.
function getOrientedCanvas(img, channelKey) {
  const channel = paperChannels[channelKey] || paperChannels['6x4'];
  const channelLong = Math.max(channel.w, channel.h);
  const channelShort = Math.min(channel.w, channel.h);
  const isImagePortrait = (img.naturalWidth || img.width) < (img.naturalHeight || img.height);

  const c = document.createElement('canvas');
  if (!isImagePortrait) {
    c.width = img.naturalWidth || img.width;
    c.height = img.naturalHeight || img.height;
    c.getContext('2d').drawImage(img, 0, 0);
  } else {
    // Rotate 90° clockwise so portrait becomes landscape: long side becomes width, short side becomes height
    const w = img.naturalWidth || img.width;
    const h = img.naturalHeight || img.height;
    c.width = h;
    c.height = w;
    const ctx = c.getContext('2d');
    ctx.translate(c.width / 2, c.height / 2);
    ctx.rotate(Math.PI / 2);
    ctx.drawImage(img, -w / 2, -h / 2);
  }
  return c;
}

// Compute standard center-crop coordinates to fit a specific target aspect ratio
function getDefaultCropForRatio(imgW, imgH, targetRatio) {
  const imageRatio = imgW / imgH;
  if (imageRatio > targetRatio) {
    const w = targetRatio / imageRatio;
    return { x: (1 - w) / 2, y: 0, w: w, h: 1 };
  } else {
    const h = imageRatio / targetRatio;
    return { x: 0, y: (1 - h) / 2, w: 1, h: h };
  }
}

// Initialize Application
function init() {
  setupEventListeners();
  if (els.hotFolderPathDisplay) els.hotFolderPathDisplay.textContent = hotFolderPath;
  if (els.outputPathDisplay) els.outputPathDisplay.textContent = outputFolderPath;
  setPrintDestination(currentPrintDestination, true);
  updateUIState();
  syncSidebarToActiveItem();
  renderSourceExplorer();
  updateGrid();
  initCameraIngest();
  
  window.addEventListener('resize', () => {
    if (viewMode === 'detail') {
      resizePreviewCanvasContainer();
    }
  });
}

// Attach DOM Event Listeners
function setupEventListeners() {
  // Hot Foil & Output Folder Selectors
  if (els.btnSelectHotFolder) els.btnSelectHotFolder.addEventListener('click', selectHotFolder);
  if (els.hotFolderPathDisplay) els.hotFolderPathDisplay.addEventListener('click', selectHotFolder);
  if (els.btnModalSelectHotFolder) els.btnModalSelectHotFolder.addEventListener('click', selectHotFolder);

  if (els.btnSelectOutput) els.btnSelectOutput.addEventListener('click', selectOutputFolder);
  if (els.outputPathDisplay) els.outputPathDisplay.addEventListener('click', selectOutputFolder);
  if (els.btnModalSelectOutput) els.btnModalSelectOutput.addEventListener('click', selectOutputFolder);

  // Print Destination Toggle (Hot Folder vs Direct Print)
  if (els.btnDestHotfolder) els.btnDestHotfolder.addEventListener('click', () => setPrintDestination('hotfolder'));
  if (els.btnDestDirect) els.btnDestDirect.addEventListener('click', () => setPrintDestination('direct'));

  // In-Software Folder Browser Modal Controls
  if (els.btnCloseFolderBrowserModal) els.btnCloseFolderBrowserModal.addEventListener('click', closeFolderBrowserModal);
  if (els.fbBtnCancel) els.fbBtnCancel.addEventListener('click', closeFolderBrowserModal);
  if (els.fbBtnSelect) els.fbBtnSelect.addEventListener('click', selectCurrentFolder);
  if (els.fbBtnGo) {
    els.fbBtnGo.addEventListener('click', () => {
      if (els.fbPathInput && els.fbPathInput.value.trim()) {
        loadDirectoryListing(els.fbPathInput.value.trim());
      }
    });
  }
  if (els.fbPathInput) {
    els.fbPathInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        if (els.fbPathInput.value.trim()) {
          loadDirectoryListing(els.fbPathInput.value.trim());
        }
      }
    });
  }
  if (els.fbBtnUp) els.fbBtnUp.addEventListener('click', navigateFolderBrowserUp);
  if (els.fbBtnNewFolder) els.fbBtnNewFolder.addEventListener('click', createNewFolderInBrowser);

  document.querySelectorAll('.fb-preset-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      const p = e.currentTarget.getAttribute('data-path');
      if (p) loadDirectoryListing(p);
    });
  });

  // Dynamic Source Selection & Windows File Management
  if (els.btnSelectSourceFolder) els.btnSelectSourceFolder.addEventListener('click', selectSourceFolder);
  if (els.sourcePathDisplay) els.sourcePathDisplay.addEventListener('click', selectSourceFolder);
  if (els.sourceDirInput) els.sourceDirInput.addEventListener('change', handleSourceDirChange);
  if (els.btnBrowseFiles) els.btnBrowseFiles.addEventListener('click', browseFiles);
  if (els.btnClearQueue) els.btnClearQueue.addEventListener('click', clearQueue);
  if (els.fileSelector) els.fileSelector.addEventListener('change', handleFileSelectorChange);
  if (els.btnSelectAll) els.btnSelectAll.addEventListener('click', () => toggleAllExplorerItems(true));
  if (els.btnDeselectAll) els.btnDeselectAll.addEventListener('click', () => toggleAllExplorerItems(false));
  if (els.sourceSearchInput) els.sourceSearchInput.addEventListener('input', renderSourceExplorer);

  // Windows Explorer Keyboard Shortcut (Ctrl+A / Cmd+A)
  window.addEventListener('keydown', (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'a') {
      if (document.activeElement && document.activeElement.tagName === 'INPUT' && document.activeElement.type === 'text') {
        return; // Allow normal text select in inputs
      }
      e.preventDefault();
      toggleAllExplorerItems(true);
    }
  });

  if (els.btnSelectArchive) els.btnSelectArchive.addEventListener('click', selectFolderArchive);

  // Paper Channel Selector
  if (els.paperChannelSelect) {
    els.paperChannelSelect.addEventListener('change', (e) => {
      activeChannel = e.target.value;
      addLog(`Changed paper channel to: ${activeChannel}`, 'info');
      showToast(`Paper channel set to ${activeChannel}`, 'success');
      
      // Auto recalculate default crops for Cut mode items
      filesQueue.forEach(item => {
        if (item.printMode === 'cut' && item.originalImageObject && !item.manualCropEdited) {
          const targetRatio = getChannelRatio(item.originalImageObject.naturalWidth, item.originalImageObject.naturalHeight, activeChannel);
          item.crop = getDefaultCropForRatio(item.originalImageObject.naturalWidth, item.originalImageObject.naturalHeight, targetRatio);
          item.isCropped = true;
        }
      });
      
      triggerPreviewRecomputation();
    });
  }

  // Template Upload
  if (els.templateInput) els.templateInput.addEventListener('change', handleTemplateUpload);
  if (els.btnRemoveTemplate) els.btnRemoveTemplate.addEventListener('click', removeTemplate);

  // Watermark Configuration Changes (Global overlay parameters)
  if (els.templateOpacity) els.templateOpacity.addEventListener('input', (e) => {
    els.opacityValue.textContent = `${e.target.value}%`;
    triggerPreviewRecomputation();
  });
  if (els.templateScale) els.templateScale.addEventListener('input', (e) => {
    els.scaleValue.textContent = `${e.target.value}%`;
    triggerPreviewRecomputation();
  });
  if (els.templatePosition) els.templatePosition.addEventListener('change', () => {
    if (els.templatePosition.value === 'center' || els.templatePosition.value === 'stretch') {
      document.getElementById('paddingGroup').style.opacity = '0.4';
      document.getElementById('paddingGroup').style.pointerEvents = 'none';
    } else {
      document.getElementById('paddingGroup').style.opacity = '1';
      document.getElementById('paddingGroup').style.pointerEvents = 'auto';
    }
    triggerPreviewRecomputation();
  });
  if (els.templateMargin) els.templateMargin.addEventListener('input', (e) => {
    els.marginValue.textContent = `${e.target.value}px`;
    triggerPreviewRecomputation();
  });

  // Sidebar Sliders - Link adjustments to the currently active item
  if (els.chkColorCorrection) els.chkColorCorrection.addEventListener('change', (e) => {
    if (!activeItem) return;
    activeItem.editParams.chkColorCorrection = e.target.checked;
    if (e.target.checked) {
      els.colorCorrectionParams.style.display = 'flex';
      els.previewRightLabel.textContent = "Color Corrected";
    } else {
      els.colorCorrectionParams.style.display = 'none';
      els.previewRightLabel.textContent = "Watermarked";
    }
    triggerPreviewRecomputation();
  });
  
  if (els.correctionAlgorithm) els.correctionAlgorithm.addEventListener('change', (e) => {
    if (!activeItem) return;
    activeItem.editParams.correctionAlgorithm = e.target.value;
    triggerPreviewRecomputation();
  });

  // Noritsu CMYD Button Listeners
  if (els.btnResetSidebarCMYD) els.btnResetSidebarCMYD.addEventListener('click', resetSidebarCMYD);
  if (els.btnCUp) els.btnCUp.addEventListener('click', () => adjustCMYD('paramC', 1));
  if (els.btnCDown) els.btnCDown.addEventListener('click', () => adjustCMYD('paramC', -1));
  
  if (els.btnMUp) els.btnMUp.addEventListener('click', () => adjustCMYD('paramM', 1));
  if (els.btnMDown) els.btnMDown.addEventListener('click', () => adjustCMYD('paramM', -1));
  
  if (els.btnYUp) els.btnYUp.addEventListener('click', () => adjustCMYD('paramY', 1));
  if (els.btnYDown) els.btnYDown.addEventListener('click', () => adjustCMYD('paramY', -1));
  
  if (els.btnDUp) els.btnDUp.addEventListener('click', () => adjustCMYD('paramD', 1));
  if (els.btnDDown) els.btnDDown.addEventListener('click', () => adjustCMYD('paramD', -1));

  if (els.paramContrast) els.paramContrast.addEventListener('input', (e) => {
    const val = parseInt(e.target.value);
    const selectedFiles = filesQueue.filter(item => item.checked);
    const startIdx = gridPage * 6;
    let targetItems = selectedFiles.slice(startIdx, startIdx + 6).filter(item => !item.passed);
    if (targetItems.length === 0 && activeItem) targetItems = [activeItem];
    targetItems.forEach(item => {
      if (!item.editParams) item.editParams = getDefaultEditParams();
      item.editParams.paramContrast = val;
    });
    if (activeItem) activeItem.editParams.paramContrast = val;
    els.contrastValue.textContent = `${val > 0 ? '+' : ''}${val}%`;
    updateGrid();
    if (viewMode === 'detail') triggerPreviewRecomputation();
  });

  if (els.paramSaturation) els.paramSaturation.addEventListener('input', (e) => {
    const val = parseInt(e.target.value);
    const selectedFiles = filesQueue.filter(item => item.checked);
    const startIdx = gridPage * 6;
    let targetItems = selectedFiles.slice(startIdx, startIdx + 6).filter(item => !item.passed);
    if (targetItems.length === 0 && activeItem) targetItems = [activeItem];
    targetItems.forEach(item => {
      if (!item.editParams) item.editParams = getDefaultEditParams();
      item.editParams.paramSaturation = val;
    });
    if (activeItem) activeItem.editParams.paramSaturation = val;
    els.saturationValue.textContent = `${val > 0 ? '+' : ''}${val}%`;
    updateGrid();
    if (viewMode === 'detail') triggerPreviewRecomputation();
  });

  // Split Slider Drag interaction (Detail mode comparison)
  if (els.comparisonSliderBar) {
    els.comparisonSliderBar.addEventListener('mousedown', startSliderDrag);
    els.comparisonSliderHandle.addEventListener('mousedown', startSliderDrag);
  }
  window.addEventListener('mousemove', handleSliderDrag);
  window.addEventListener('mouseup', stopSliderDrag);

  // Queue Search Filter
  if (els.queueSearch) els.queueSearch.addEventListener('input', renderQueue);

  // Batch Control
  if (els.btnStartProcess) els.btnStartProcess.addEventListener('click', startBatchProcessing);
  if (els.btnPauseProcess) els.btnPauseProcess.addEventListener('click', pauseBatchProcessing);
  
  // View Toggle Controls
  if (els.btnToggleViewMode) els.btnToggleViewMode.addEventListener('click', () => switchToDetailView(false));
  if (els.btnBackToGrid) els.btnBackToGrid.addEventListener('click', switchToGridView);
  
  // Grid mode specific buttons
  if (els.btnPrevPage) els.btnPrevPage.addEventListener('click', () => navigateGridPage(-1));
  if (els.btnNextPage) els.btnNextPage.addEventListener('click', () => navigateGridPage(1));
  if (els.btnPrintPageAll) els.btnPrintPageAll.addEventListener('click', printActiveGridPage);
  
  // Detail mode specific buttons
  if (els.btnToggleCropTool) els.btnToggleCropTool.addEventListener('click', toggleCropMode);
  if (els.btnResetCrop) els.btnResetCrop.addEventListener('click', resetCropCoordinates);
  if (els.btnPrintDetail) els.btnPrintDetail.addEventListener('click', () => {
    if (activeItem) printImage(activeItem);
  });
  
  if (els.btnDetailModeCut) {
    els.btnDetailModeCut.addEventListener('click', () => {
      if (activeItem) setPrintMode(activeItem, 'cut');
    });
  }
  if (els.btnDetailModeOverall) {
    els.btnDetailModeOverall.addEventListener('click', () => {
      if (activeItem) setPrintMode(activeItem, 'overall');
    });
  }
  
  // Crop interactive handlers
  if (els.cropBox) els.cropBox.addEventListener('mousedown', handleCropMouseDown);
  if (els.cropOverlay) {
    els.cropOverlay.querySelectorAll('.crop-handle').forEach(h => {
      h.addEventListener('mousedown', handleCropMouseDown);
    });
  }
  window.addEventListener('mousemove', handleCropMouseMove);
  window.addEventListener('mouseup', handleCropMouseUp);

  // Auto Mode toggle
  if (els.chkAutoMode) {
    els.chkAutoMode.checked = isAutoMode;
    els.chkAutoMode.addEventListener('change', (e) => setAutoMode(e.target.checked));
  }
  if (isAutoMode && els.gridModeContainer) {
    els.gridModeContainer.classList.add('auto-mode-active');
  }

  // Settings Modal handlers
  if (els.btnOpenSettings) els.btnOpenSettings.addEventListener('click', openSettingsModal);
  if (els.btnQuickSettings) els.btnQuickSettings.addEventListener('click', openSettingsModal);
  if (els.btnCloseSettingsModal) els.btnCloseSettingsModal.addEventListener('click', closeSettingsModal);
  if (els.btnCancelSettings) els.btnCancelSettings.addEventListener('click', closeSettingsModal);
  if (els.btnSaveSettings) els.btnSaveSettings.addEventListener('click', saveSettingsModal);

  if (els.settingColorStep) {
    els.settingColorStep.addEventListener('input', (e) => {
      if (els.colorStepValDisplay) els.colorStepValDisplay.textContent = parseFloat(e.target.value).toFixed(1) + '%';
    });
  }
  if (els.settingDensityStep) {
    els.settingDensityStep.addEventListener('input', (e) => {
      if (els.densityStepValDisplay) els.densityStepValDisplay.textContent = parseFloat(e.target.value).toFixed(1) + '%';
    });
  }
  if (els.btnModalSelectHotFolder) {
    els.btnModalSelectHotFolder.addEventListener('click', () => {
      if (els.btnSelectHotFolder) els.btnSelectHotFolder.click();
      setTimeout(syncModalFolderDisplays, 600);
    });
  }
  if (els.btnModalSelectOutput) {
    els.btnModalSelectOutput.addEventListener('click', () => {
      if (els.btnSelectOutput) els.btnSelectOutput.click();
      setTimeout(syncModalFolderDisplays, 600);
    });
  }
  updateSidebarStepDisplays();

  // 1:1 Magnification Button
  if (els.btnZoom1to1) els.btnZoom1to1.addEventListener('click', toggle1to1Zoom);

  // Single-Frame Floating Context Menu
  if (els.previewViewport) {
    els.previewViewport.addEventListener('contextmenu', (e) => {
      if (viewMode !== 'detail') return;
      e.preventDefault();
      e.stopPropagation();
      showSingleFrameContextMenu(e.clientX, e.clientY);
    });
  }
  document.addEventListener('click', (e) => {
    if (els.singleFrameContextMenu && !els.singleFrameContextMenu.contains(e.target)) {
      els.singleFrameContextMenu.style.display = 'none';
    }
  });
  if (els.ctxCropBtn) els.ctxCropBtn.addEventListener('click', () => {
    if (els.singleFrameContextMenu) els.singleFrameContextMenu.style.display = 'none';
    toggleCropMode();
  });
  if (els.ctxZoomBtn) els.ctxZoomBtn.addEventListener('click', () => {
    if (els.singleFrameContextMenu) els.singleFrameContextMenu.style.display = 'none';
    toggle1to1Zoom();
  });
  if (els.ctxResetCropBtn) els.ctxResetCropBtn.addEventListener('click', () => {
    if (els.singleFrameContextMenu) els.singleFrameContextMenu.style.display = 'none';
    resetCropCoordinates();
  });
  if (els.ctxBackBtn) els.ctxBackBtn.addEventListener('click', () => {
    if (els.singleFrameContextMenu) els.singleFrameContextMenu.style.display = 'none';
    switchToGridView();
  });
}

// ----------------------------------------------------
// Auto Mode Switch Functionality
// ----------------------------------------------------
function setAutoMode(enabled) {
  isAutoMode = !!enabled;
  localStorage.setItem('gs_auto_mode', String(isAutoMode));
  if (els.chkAutoMode) els.chkAutoMode.checked = isAutoMode;
  if (els.gridModeContainer) {
    els.gridModeContainer.classList.toggle('auto-mode-active', isAutoMode);
  }
  showToast(`Auto Mode ${isAutoMode ? 'ENABLED: Color keys hidden for fast processing' : 'DISABLED: Color keys enabled'}`, 'info');
}

// ----------------------------------------------------
// Settings Modal Functionality
// ----------------------------------------------------
function openSettingsModal() {
  if (!els.settingsModal) return;
  if (els.settingColorStep) {
    els.settingColorStep.value = colorStepPct;
    if (els.colorStepValDisplay) els.colorStepValDisplay.textContent = colorStepPct.toFixed(1) + '%';
  }
  if (els.settingDensityStep) {
    els.settingDensityStep.value = densityStepPct;
    if (els.densityStepValDisplay) els.densityStepValDisplay.textContent = densityStepPct.toFixed(1) + '%';
  }
  syncModalFolderDisplays();
  els.settingsModal.style.display = 'flex';
}

function closeSettingsModal() {
  if (els.settingsModal) els.settingsModal.style.display = 'none';
}

function syncModalFolderDisplays() {
  if (els.modalHotFolderDisplay) els.modalHotFolderDisplay.textContent = hotFolderPath;
  if (els.modalOutputDisplay) els.modalOutputDisplay.textContent = outputFolderPath;
}

function saveSettingsModal() {
  if (els.settingColorStep) {
    colorStepPct = Math.max(0.5, Math.min(20.0, parseFloat(els.settingColorStep.value) || 2.5));
    localStorage.setItem('gs_color_step_pct', String(colorStepPct));
  }
  if (els.settingDensityStep) {
    densityStepPct = Math.max(0.5, Math.min(20.0, parseFloat(els.settingDensityStep.value) || 2.5));
    localStorage.setItem('gs_density_step_pct', String(densityStepPct));
  }
  updateSidebarStepDisplays();
  closeSettingsModal();
  updateGrid();
  if (viewMode === 'detail' && activeItem) {
    recomputeProcessedPreview();
  }
  showToast(`Settings applied: Color Step ${colorStepPct.toFixed(1)}%, Density Step ${densityStepPct.toFixed(1)}%`, 'success');
}

function updateSidebarStepDisplays() {
  if (els.sidebarColorPctDisplay) els.sidebarColorPctDisplay.textContent = colorStepPct.toFixed(1) + '%';
  if (els.sidebarDensityPctDisplay) els.sidebarDensityPctDisplay.textContent = densityStepPct.toFixed(1) + '%';
}

// ----------------------------------------------------
// 1:1 Magnification & Context Menu
// ----------------------------------------------------
function toggle1to1Zoom() {
  if (viewMode !== 'detail' || !activeItem) return;
  is1to1Zoom = !is1to1Zoom;
  if (is1to1Zoom) {
    if (els.previewViewport) els.previewViewport.classList.add('zoom-1to1');
    if (els.btnZoom1to1) {
      els.btnZoom1to1.innerHTML = `<i class="fa-solid fa-compress"></i> Fit Screen`;
      els.btnZoom1to1.classList.add('btn-accent');
    }
    if (els.ctxZoomBtn) {
      els.ctxZoomBtn.innerHTML = `<i class="fa-solid fa-compress" style="color: var(--accent);"></i> Fit Screen`;
    }
  } else {
    if (els.previewViewport) els.previewViewport.classList.remove('zoom-1to1');
    if (els.btnZoom1to1) {
      els.btnZoom1to1.innerHTML = `<i class="fa-solid fa-magnifying-glass-plus"></i> 1:1 Zoom`;
      els.btnZoom1to1.classList.remove('btn-accent');
    }
    if (els.ctxZoomBtn) {
      els.ctxZoomBtn.innerHTML = `<i class="fa-solid fa-magnifying-glass-plus" style="color: var(--accent);"></i> 1:1 Magnification`;
    }
  }
  recomputeProcessedPreview();
}

function showSingleFrameContextMenu(x, y) {
  if (!els.singleFrameContextMenu) return;
  els.singleFrameContextMenu.style.left = `${Math.min(window.innerWidth - 220, Math.max(10, x))}px`;
  els.singleFrameContextMenu.style.top = `${Math.min(window.innerHeight - 220, Math.max(10, y))}px`;
  els.singleFrameContextMenu.style.display = 'flex';
}

// Adjust Noritsu-style CMYD parameter across all images selected in the 6-frame screen
function adjustCMYD(paramName, direction) {
  const selectedFiles = filesQueue.filter(item => item.checked);
  const startIdx = gridPage * 6;
  let targetItems = selectedFiles.slice(startIdx, startIdx + 6).filter(item => !item.passed);
  
  if (targetItems.length === 0) {
    if (activeItem && !activeItem.passed) targetItems = [activeItem];
    else targetItems = filesQueue.filter(item => item.checked && !item.passed);
  }
  
  if (targetItems.length === 0) {
    showToast('No photos selected in 6-frame screen to adjust', 'warning');
    return;
  }
  
  // Apply adjustment to ALL images selected in the 6-frame screen
  targetItems.forEach(item => {
    if (!item.editParams) item.editParams = getDefaultEditParams();
    item.editParams[paramName] = Math.max(-20, Math.min(20, (item.editParams[paramName] || 0) + direction));
  });
  
  if (!activeItem || !targetItems.includes(activeItem)) {
    activeItem = targetItems[0];
  }
  
  updateCMYDDisplay();
  updateGrid();
  
  if (viewMode === 'detail') {
    triggerPreviewRecomputation();
  }
}

function resetSidebarCMYD() {
  const selectedFiles = filesQueue.filter(item => item.checked);
  const startIdx = gridPage * 6;
  let targetItems = selectedFiles.slice(startIdx, startIdx + 6).filter(item => !item.passed);
  
  if (targetItems.length === 0) {
    if (activeItem && !activeItem.passed) targetItems = [activeItem];
    else targetItems = filesQueue.filter(item => item.checked && !item.passed);
  }
  
  if (targetItems.length === 0) return;
  
  targetItems.forEach(item => {
    if (!item.editParams) item.editParams = getDefaultEditParams();
    item.editParams.paramC = 0;
    item.editParams.paramM = 0;
    item.editParams.paramY = 0;
    item.editParams.paramD = 0;
  });
  
  updateCMYDDisplay();
  updateGrid();
  if (viewMode === 'detail') triggerPreviewRecomputation();
  showToast(`Color balance reset for ${targetItems.length} frame(s)`, 'info');
}

// Sync values to DOM view badges
function updateCMYDDisplay() {
  if (!activeItem) {
    if (els.valC) els.valC.textContent = '0';
    if (els.valM) els.valM.textContent = '0';
    if (els.valY) els.valY.textContent = '0';
    if (els.valD) els.valD.textContent = '0';
    return;
  }
  
  const ep = activeItem.editParams;
  if (els.valC) els.valC.textContent = (ep.paramC > 0 ? '+' : '') + ep.paramC;
  if (els.valM) els.valM.textContent = (ep.paramM > 0 ? '+' : '') + ep.paramM;
  if (els.valY) els.valY.textContent = (ep.paramY > 0 ? '+' : '') + ep.paramY;
  if (els.valD) els.valD.textContent = (ep.paramD > 0 ? '+' : '') + ep.paramD;
}

// Change item sizing fit mode (Cut vs. Overall) and apply respective cropping defaults
function setPrintMode(item, mode) {
  item.printMode = mode;
  
  // Sync Detail Toolbar states
  if (viewMode === 'detail' && activeItem && activeItem.name === item.name) {
    if (mode === 'cut') {
      els.btnDetailModeCut.classList.add('active');
      els.btnDetailModeOverall.classList.remove('active');
    } else {
      els.btnDetailModeCut.classList.remove('active');
      els.btnDetailModeOverall.classList.add('active');
    }
  }
  
  // Adjust Crop coordinates based on layout mode chosen
  if (mode === 'cut' && item.originalImageObject) {
    const targetRatio = getChannelRatio(item.originalImageObject.naturalWidth, item.originalImageObject.naturalHeight, activeChannel);
    item.crop = getDefaultCropForRatio(item.originalImageObject.naturalWidth, item.originalImageObject.naturalHeight, targetRatio);
    item.isCropped = true;
  } else if (mode === 'overall') {
    // Reset crop on overall unless the user has manually clicked/dragged a crop box
    if (!item.manualCropEdited) {
      item.crop = { x: 0, y: 0, w: 1, h: 1 };
      item.isCropped = false;
    }
  }
  
  triggerPreviewRecomputation();
}

// ----------------------------------------------------
// File Browsing & Folder Management (Hot Foil & Source)
// ----------------------------------------------------

// ----------------------------------------------------
// HTML Sanitization Helper
// ----------------------------------------------------
function escapeHtml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

// ----------------------------------------------------
// Print Destination Toggle (Hot Folder vs Direct Print)
// ----------------------------------------------------
function setPrintDestination(dest, skipToast) {
  currentPrintDestination = (dest === 'direct') ? 'direct' : 'hotfolder';
  localStorage.setItem('gs_print_destination', currentPrintDestination);

  if (els.btnDestHotfolder && els.btnDestDirect) {
    if (currentPrintDestination === 'direct') {
      els.btnDestDirect.classList.add('active');
      els.btnDestHotfolder.classList.remove('active');
      if (els.printDestDescription) {
        els.printDestDescription.textContent = `Direct Print ENABLED: Corrected photos are sent directly to Windows Default Printer on Channel ${activeChannel.toUpperCase()}. Source photos are archived in Output Folder.`;
      }
      if (els.hotFolderStatus) {
        els.hotFolderStatus.textContent = 'Bypassed (Direct Print)';
        els.hotFolderStatus.style.background = 'rgba(100, 116, 139, 0.2)';
        els.hotFolderStatus.style.color = '#94a3b8';
      }
    } else {
      els.btnDestHotfolder.classList.add('active');
      els.btnDestDirect.classList.remove('active');
      if (els.printDestDescription) {
        els.printDestDescription.textContent = 'Hot Foil Facility ENABLED: Corrected photos are dispatched to Hot Folder for the hot foil machine. Source photos are archived in Output Folder.';
      }
      if (els.hotFolderStatus) {
        els.hotFolderStatus.textContent = 'Active Hot Folder';
        els.hotFolderStatus.style.background = 'rgba(245, 158, 11, 0.15)';
        els.hotFolderStatus.style.color = '#f59e0b';
      }
    }
  }

  if (!skipToast) {
    showToast(
      currentPrintDestination === 'direct'
        ? 'Direct Print Mode active (prints directly to Windows default printer)'
        : 'Hot Folder Mode active (dispatches photos to Hot Foil folder)',
      'info'
    );
  }
}

// ----------------------------------------------------
// In-Software Folder Browser Implementation
// ----------------------------------------------------
let fbCurrentParent = '';

function openFolderBrowser(targetField) {
  fbTarget = targetField || 'hotfolder';
  
  if (fbTarget === 'hotfolder') {
    fbCurrentPath = hotFolderPath || 'C:\\Fujifilm_Hotfolder';
    if (els.fbModalTitle) els.fbModalTitle.innerHTML = '<i class="fa-solid fa-fire-flame-curved" style="color: #f59e0b;"></i> Browse Hot Folder (Hot Foil Facility)';
    if (els.fbTargetName) els.fbTargetName.textContent = 'Hot Folder (Hot Foil Facility)';
  } else if (fbTarget === 'output') {
    fbCurrentPath = outputFolderPath || 'Printed_Photos';
    if (els.fbModalTitle) els.fbModalTitle.innerHTML = '<i class="fa-solid fa-folder-closed" style="color: #10b981;"></i> Browse Output Folder (Processed Photos)';
    if (els.fbTargetName) els.fbTargetName.textContent = 'Output Folder (Processed Photos)';
  } else if (fbTarget === 'camera') {
    fbCurrentPath = cameraTargetFolder || 'C:\\GS_Event\\Camera_Incoming';
    if (els.fbModalTitle) els.fbModalTitle.innerHTML = '<i class="fa-solid fa-camera" style="color: #10b981;"></i> Browse Camera Incoming Folder';
    if (els.fbTargetName) els.fbTargetName.textContent = 'Camera Incoming Folder';
  } else {
    fbCurrentPath = 'C:\\';
    if (els.fbModalTitle) els.fbModalTitle.innerHTML = '<i class="fa-solid fa-folder-tree" style="color: var(--primary);"></i> Browse Directory';
    if (els.fbTargetName) els.fbTargetName.textContent = 'Directory';
  }

  if (els.fbPathInput) els.fbPathInput.value = fbCurrentPath;
  if (els.fbSelectedPathPreview) els.fbSelectedPathPreview.textContent = fbCurrentPath;
  if (els.folderBrowserModal) els.folderBrowserModal.style.display = 'flex';

  loadDirectoryListing(fbCurrentPath);
}

function closeFolderBrowserModal() {
  if (els.folderBrowserModal) els.folderBrowserModal.style.display = 'none';
}

async function loadDirectoryListing(targetPath) {
  if (!targetPath) targetPath = 'C:\\';
  if (els.fbDirList) {
    els.fbDirList.innerHTML = `
      <div style="text-align: center; color: var(--text-muted); padding: 3rem 1rem; font-size: 0.8rem;">
        <i class="fa-solid fa-spinner fa-spin" style="margin-right: 0.4rem;"></i> Reading directories...
      </div>
    `;
  }

  try {
    const res = await fetch('/api/browse-directory', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ path: targetPath })
    });

    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();

    fbCurrentPath = data.currentPath || targetPath;
    fbCurrentParent = data.parentPath || '';

    if (els.fbPathInput) els.fbPathInput.value = fbCurrentPath;
    if (els.fbSelectedPathPreview) els.fbSelectedPathPreview.textContent = fbCurrentPath;

    // Render Drive buttons
    if (els.fbDrivesContainer && Array.isArray(data.drives)) {
      els.fbDrivesContainer.innerHTML = '';
      data.drives.forEach(drv => {
        const btn = document.createElement('button');
        btn.type = 'button';
        btn.className = 'btn btn-xs btn-outline';
        btn.style.padding = '2px 7px';
        btn.style.fontSize = '0.68rem';
        btn.textContent = drv;
        btn.addEventListener('click', () => loadDirectoryListing(drv));
        els.fbDrivesContainer.appendChild(btn);
      });
    }

    // Render subdirectories in list
    if (els.fbDirList) {
      els.fbDirList.innerHTML = '';

      // Up to parent item
      if (data.parentPath) {
        const parentItem = document.createElement('div');
        parentItem.className = 'fb-dir-item';
        parentItem.innerHTML = `
          <i class="fa-solid fa-arrow-turn-up" style="color: var(--accent); width: 18px; text-align: center;"></i>
          <span style="font-weight: 600;">.. (Up to ${escapeHtml(data.parentPath)})</span>
        `;
        parentItem.addEventListener('click', () => {
          loadDirectoryListing(data.parentPath);
        });
        els.fbDirList.appendChild(parentItem);
      }

      if (!data.subdirs || data.subdirs.length === 0) {
        const emptyMsg = document.createElement('div');
        emptyMsg.style.padding = '1.5rem 1rem';
        emptyMsg.style.textAlign = 'center';
        emptyMsg.style.color = 'var(--text-muted)';
        emptyMsg.style.fontSize = '0.75rem';
        emptyMsg.innerHTML = '<i class="fa-regular fa-folder-open"></i> No subdirectories in this folder';
        els.fbDirList.appendChild(emptyMsg);
      } else {
        data.subdirs.forEach(sub => {
          const fullSubPath = fbCurrentPath.endsWith('\\') || fbCurrentPath.endsWith('/') 
            ? `${fbCurrentPath}${sub}` 
            : `${fbCurrentPath}\\${sub}`;

          const itemEl = document.createElement('div');
          itemEl.className = 'fb-dir-item';
          itemEl.innerHTML = `
            <i class="fa-solid fa-folder" style="color: #f59e0b; width: 18px; text-align: center;"></i>
            <span style="flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${escapeHtml(sub)}</span>
          `;

          // Single click selects
          itemEl.addEventListener('click', () => {
            document.querySelectorAll('.fb-dir-item').forEach(el => el.classList.remove('selected'));
            itemEl.classList.add('selected');
            if (els.fbSelectedPathPreview) els.fbSelectedPathPreview.textContent = fullSubPath;
          });

          // Double click navigates into
          itemEl.addEventListener('dblclick', () => {
            loadDirectoryListing(fullSubPath);
          });

          els.fbDirList.appendChild(itemEl);
        });
      }
    }

  } catch (err) {
    if (els.fbDirList) {
      els.fbDirList.innerHTML = `
        <div style="padding: 1.5rem 1rem; text-align: center; color: var(--danger); font-size: 0.78rem;">
          <i class="fa-solid fa-triangle-exclamation"></i> Unable to browse folder directly: ${escapeHtml(err.message)}<br>
          <span style="color: var(--text-muted); font-size: 0.72rem; margin-top: 4px; display: block;">You can still type the path manually in the box above.</span>
        </div>
      `;
    }
  }
}

function navigateFolderBrowserUp() {
  if (fbCurrentParent) {
    loadDirectoryListing(fbCurrentParent);
  } else {
    const lastSlash = Math.max(fbCurrentPath.lastIndexOf('\\'), fbCurrentPath.lastIndexOf('/'));
    if (lastSlash > 2) {
      loadDirectoryListing(fbCurrentPath.substring(0, lastSlash));
    }
  }
}

async function createNewFolderInBrowser() {
  const folderName = window.prompt("Enter new folder name to create inside:\n" + fbCurrentPath, "New_Folder");
  if (!folderName || !folderName.trim()) return;

  const newPath = (fbCurrentPath.endsWith('\\') || fbCurrentPath.endsWith('/'))
    ? `${fbCurrentPath}${folderName.trim()}`
    : `${fbCurrentPath}\\${folderName.trim()}`;

  try {
    const res = await fetch('/api/create-directory', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ path: newPath })
    });
    if (res.ok) {
      showToast(`Created folder: ${folderName.trim()}`, 'success');
      loadDirectoryListing(newPath);
    } else {
      throw new Error("Server returned error creating directory");
    }
  } catch (e) {
    showToast(`Failed to create directory: ${e.message}`, 'error');
  }
}

function selectCurrentFolder() {
  const chosen = (els.fbSelectedPathPreview && els.fbSelectedPathPreview.textContent.trim()) 
    ? els.fbSelectedPathPreview.textContent.trim() 
    : (els.fbPathInput ? els.fbPathInput.value.trim() : fbCurrentPath);

  if (!chosen) {
    showToast('Please select a directory path.', 'warning');
    return;
  }

  if (fbTarget === 'hotfolder') {
    hotFolderPath = chosen;
    localStorage.setItem('gs_hot_folder', hotFolderPath);
    if (els.hotFolderPathDisplay) els.hotFolderPathDisplay.textContent = hotFolderPath;
    if (els.modalHotFolderDisplay) els.modalHotFolderDisplay.textContent = hotFolderPath;
    addLog(`[Hot Foil] Hot folder assigned: ${hotFolderPath}`, 'success');
    showToast(`Hot folder set to: ${hotFolderPath}`, 'success');
  } else if (fbTarget === 'output') {
    outputFolderPath = chosen;
    localStorage.setItem('gs_output_folder', outputFolderPath);
    if (els.outputPathDisplay) els.outputPathDisplay.textContent = outputFolderPath;
    if (els.modalOutputDisplay) els.modalOutputDisplay.textContent = outputFolderPath;
    addLog(`[Output] Output folder assigned: ${outputFolderPath}`, 'success');
    showToast(`Output folder set to: ${outputFolderPath}`, 'success');
  } else if (fbTarget === 'camera') {
    cameraTargetFolder = chosen;
    if (els.camTargetFolderDisplay) els.camTargetFolderDisplay.textContent = chosen;
    setCameraTargetFolder(chosen);
    addLog(`[Camera] Ingest folder assigned: ${chosen}`, 'success');
    showToast(`Camera ingest folder set to: ${chosen}`, 'success');
  }

  closeFolderBrowserModal();
}

function selectHotFolder() {
  openFolderBrowser('hotfolder');
}

function selectOutputFolder() {
  openFolderBrowser('output');
}

// ─────────────────────────────────────────────────────────────
//  WI-FI CAMERA INGEST & MONITORING
// ─────────────────────────────────────────────────────────────
let cameraServerActive = false;
let cameraServerPort = 2121;
let cameraHostIp = '127.0.0.1';
let cameraHotspotIp = '';
let cameraTargetFolder = 'C:\\GS_Event\\Camera_Incoming';
let cameraAutoIngest = localStorage.getItem('gs_camera_auto_ingest') !== 'false';
let cameraPollTimer = null;
const knownCameraFiles = new Set();
let cameraReceivedCount = 0;
let cameraIngestInitialized = false;

function initCameraIngest() {
  if (cameraIngestInitialized) {
    fetchCameraStatus();
    return;
  }
  cameraIngestInitialized = true;

  // Sync checkbox state
  if (els.chkCameraAutoIngest) {
    els.chkCameraAutoIngest.checked = cameraAutoIngest;
    els.chkCameraAutoIngest.addEventListener('change', (e) => {
      cameraAutoIngest = e.target.checked;
      localStorage.setItem('gs_camera_auto_ingest', String(cameraAutoIngest));
      showToast(`Camera Auto-Ingest: ${cameraAutoIngest ? 'ENABLED' : 'DISABLED'}`, 'info');
    });
  }

  // Splash card button
  if (els.btnOpenSplashCameraTool) {
    els.btnOpenSplashCameraTool.addEventListener('click', openCameraModal);
  }
  if (els.btnSplashOpenCamModal) {
    els.btnSplashOpenCamModal.addEventListener('click', (e) => {
      e.stopPropagation();
      openCameraModal();
    });
  }

  // Studio Pro setup button
  if (els.btnOpenStudioCameraSettings) {
    els.btnOpenStudioCameraSettings.addEventListener('click', openCameraModal);
  }

  // Modal close buttons
  if (els.btnCloseCameraModal) els.btnCloseCameraModal.addEventListener('click', closeCameraModal);
  if (els.btnCamModalCancel) els.btnCamModalCancel.addEventListener('click', closeCameraModal);

  // Launch Studio Pro from modal
  if (els.btnLaunchStudioFromCameraModal) {
    els.btnLaunchStudioFromCameraModal.addEventListener('click', () => {
      closeCameraModal();
      selectMode('studio');
      if (els.chkCameraAutoIngest) els.chkCameraAutoIngest.checked = true;
      cameraAutoIngest = true;
      localStorage.setItem('gs_camera_auto_ingest', 'true');
    });
  }

  // Copy IP button
  if (els.btnCopyCamIp) {
    els.btnCopyCamIp.addEventListener('click', () => {
      const ip = cameraHostIp || '127.0.0.1';
      if (navigator.clipboard) {
        navigator.clipboard.writeText(ip).then(() => {
          showToast(`Copied Camera Host IP: ${ip}`, 'success');
        });
      }
    });
  }

  // Toggle server button
  if (els.btnToggleCameraServer) {
    els.btnToggleCameraServer.addEventListener('click', toggleCameraServer);
  }

  // Change camera target folder button
  if (els.btnChangeCamTargetFolder) {
    els.btnChangeCamTargetFolder.addEventListener('click', () => {
      openFolderBrowser('camera');
    });
  }

  // Brand tabs in modal
  document.querySelectorAll('.cam-tab-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.cam-tab-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      const brand = btn.getAttribute('data-brand');
      ['sony', 'canon', 'nikon', 'fuji'].forEach(b => {
        const pane = document.getElementById('camGuide' + b.charAt(0).toUpperCase() + b.slice(1));
        if (pane) pane.style.display = (b === brand) ? 'block' : 'none';
      });
    });
  });

  // Fetch initial status and start polling
  fetchCameraStatus();
  if (!cameraPollTimer) {
    cameraPollTimer = setInterval(pollCameraIncoming, 1600);
  }
}

async function fetchCameraStatus() {
  try {
    const res = await fetch('/api/camera/status');
    if (!res.ok) return;
    const data = await res.json();
    applyCameraStatus(data);
  } catch (err) {}
}

function applyCameraStatus(data) {
  if (!data) return;
  cameraServerActive = !!data.isRunning;
  cameraServerPort = data.port || 2121;
  cameraHostIp = data.primaryIp || '127.0.0.1';
  cameraHotspotIp = data.hotspotIp || '';
  cameraTargetFolder = data.targetFolder || 'C:\\GS_Event\\Camera_Incoming';
  cameraReceivedCount = data.totalReceived || 0;

  // Update UI indicators
  const statusColor = cameraServerActive ? '#10b981' : '#ef4444';
  const statusBg = cameraServerActive ? 'rgba(16, 185, 129, 0.2)' : 'rgba(239, 68, 68, 0.2)';
  const statusBorder = cameraServerActive ? 'rgba(16, 185, 129, 0.4)' : 'rgba(239, 68, 68, 0.4)';
  const statusLabel = cameraServerActive ? `● Listening (${cameraServerPort})` : '● Stopped';

  if (els.splashCameraPill) {
    els.splashCameraPill.innerHTML = cameraServerActive 
      ? `<i class="fa-solid fa-wifi"></i> Ready (Port ${cameraServerPort})` 
      : `<i class="fa-solid fa-power-off"></i> Off`;
    els.splashCameraPill.style.color = statusColor;
    els.splashCameraPill.style.background = statusBg;
    els.splashCameraPill.style.borderColor = statusBorder;
  }

  if (els.cameraLivePill) {
    els.cameraLivePill.textContent = statusLabel;
    els.cameraLivePill.style.color = statusColor;
    els.cameraLivePill.style.background = statusBg;
    els.cameraLivePill.style.borderColor = statusBorder;
  }

  if (els.camServerStatusIndicator) {
    els.camServerStatusIndicator.style.background = statusColor;
    els.camServerStatusIndicator.style.boxShadow = `0 0 8px ${statusColor}`;
  }

  if (els.camServerStatusText) {
    els.camServerStatusText.style.color = statusColor;
    els.camServerStatusText.textContent = cameraServerActive 
      ? `Camera Ingest Server: Active (Port ${cameraServerPort})` 
      : 'Camera Ingest Server: Stopped';
  }

  if (els.btnToggleCameraServer) {
    els.btnToggleCameraServer.innerHTML = cameraServerActive 
      ? '<i class="fa-solid fa-stop"></i> Stop Service' 
      : '<i class="fa-solid fa-play"></i> Start Service';
  }

  if (els.camHostIpDisplay) {
    els.camHostIpDisplay.textContent = cameraHostIp;
  }

  // Update brand guides IP code
  document.querySelectorAll('.cam-guide-ip').forEach(el => {
    el.textContent = cameraHostIp;
  });

  if (els.camTargetFolderDisplay) {
    els.camTargetFolderDisplay.textContent = cameraTargetFolder;
  }

  if (els.camTotalShotsBadge) {
    els.camTotalShotsBadge.textContent = `${cameraReceivedCount} shots received`;
  }
}

async function toggleCameraServer() {
  try {
    const res = await fetch('/api/camera/toggle', { method: 'POST' });
    if (res.ok) {
      const data = await res.json();
      cameraServerActive = !!data.isRunning;
      fetchCameraStatus();
      showToast(`Camera Ingest Server ${cameraServerActive ? 'STARTED' : 'STOPPED'}`, cameraServerActive ? 'success' : 'info');
    }
  } catch (err) {
    showToast('Failed toggling camera server: ' + err.message, 'error');
  }
}

async function setCameraTargetFolder(folder) {
  try {
    const res = await fetch('/api/camera/set-folder', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ folder: folder })
    });
    if (res.ok) {
      fetchCameraStatus();
    }
  } catch (e) {}
}

function openCameraModal() {
  if (els.cameraSetupModal) {
    els.cameraSetupModal.style.display = 'flex';
    fetchCameraStatus();
    pollCameraIncoming();
  }
}

function closeCameraModal() {
  if (els.cameraSetupModal) {
    els.cameraSetupModal.style.display = 'none';
  }
}

async function pollCameraIncoming() {
  try {
    const res = await fetch('/api/camera/incoming');
    if (!res.ok) return;
    const data = await res.json();
    if (!data || !Array.isArray(data.files)) return;

    // Process files from oldest to newest
    const sorted = [...data.files].sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));
    for (const f of sorted) {
      if (!knownCameraFiles.has(f.filePath)) {
        handleIncomingCameraPhoto(f);
      }
    }
  } catch (err) {}
}

function handleIncomingCameraPhoto(f) {
  knownCameraFiles.add(f.filePath);

  // Add to Modal Live Arrivals feed
  if (els.camRecentArrivalsList) {
    if (els.camEmptyFeedMsg) els.camEmptyFeedMsg.style.display = 'none';

    const itemEl = document.createElement('div');
    itemEl.className = 'cam-recent-item';
    const timeStr = f.timestamp ? new Date(f.timestamp).toLocaleTimeString() : '';
    const sizeStr = formatBytes(f.fileSize || 0);

    itemEl.innerHTML = `
      <i class="fa-solid fa-camera" style="color: #10b981; font-size: 1rem;"></i>
      <div style="flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
        <strong style="color: var(--text-primary); font-family: monospace;">${escapeHtml(f.fileName)}</strong>
        <div style="font-size: 0.65rem; color: var(--text-muted);">${timeStr} · ${sizeStr}</div>
      </div>
      <span style="font-size: 0.65rem; padding: 1px 6px; border-radius: 4px; background: rgba(16, 185, 129, 0.2); color: #10b981; font-weight: 700;">RECEIVED</span>
    `;
    els.camRecentArrivalsList.insertBefore(itemEl, els.camRecentArrivalsList.firstChild);
  }

  // If in Studio Pro mode and Auto-Ingest is active:
  if (appMode === 'studio' && cameraAutoIngest) {
    addLog(`[Wi-Fi Camera] Auto-ingested ${f.fileName} into queue`, 'success');
    showToast(`📷 Camera shot received: ${f.fileName}`, 'success');

    const newItem = {
      id: 'cam_' + Date.now() + '_' + Math.random().toString(36).substring(2, 6),
      name: f.fileName,
      file: null,
      handle: null,
      path: f.filePath,
      url: f.url,
      sizeStr: formatBytes(f.fileSize || 0),
      checked: true,
      passed: false,
      qty: 1,
      printMode: 'overall',
      manualCropEdited: false,
      crop: { x: 0, y: 0, w: 1, h: 1 },
      isCropped: false,
      editParams: getDefaultEditParams(),
      dateModified: new Date()
    };

    // Prepend so the newest shot appears at the top / frame 1
    filesQueue.unshift(newItem);
    renderSourceExplorer();
    updateGrid();
    updateUIState();
  }
}

// ─────────────────────────────────────────────────────────────
//  MOBILE CUSTOMER UPLOADS & STUDIO PRO INTEGRATION
// ─────────────────────────────────────────────────────────────
let mobileAutoIngest = true;
let knownMobileFiles = new Set();
let mobilePollTimer = null;
let mobileReceivedCount = 0;
let mobileQrUrl = '';
let mobileWifiSsid = '';
let mobileStudioQRInstance = null;

function initMobileUploads() {
  const btnHeader = document.getElementById('btnOpenMobileModal');
  if (btnHeader) btnHeader.addEventListener('click', openMobileStudioModal);

  const btnStudio = document.getElementById('btnOpenStudioMobileModal');
  if (btnStudio) btnStudio.addEventListener('click', openMobileStudioModal);

  const btnClose = document.getElementById('btnCloseMobileStudioModal');
  if (btnClose) btnClose.addEventListener('click', closeMobileStudioModal);

  const btnClose2 = document.getElementById('btnCloseMobileStudioModal2');
  if (btnClose2) btnClose2.addEventListener('click', closeMobileStudioModal);

  const btnRefresh = document.getElementById('btnRefreshMobilePhotos');
  if (btnRefresh) btnRefresh.addEventListener('click', pollMobileUploads);

  const btnImportAll = document.getElementById('btnImportAllMobile');
  if (btnImportAll) btnImportAll.addEventListener('click', importAllMobileToStudio);

  const chkAuto = document.getElementById('chkMobileAutoIngest');
  if (chkAuto) {
    chkAuto.addEventListener('change', (e) => {
      mobileAutoIngest = e.target.checked;
      showToast(`Mobile Auto-Load ${mobileAutoIngest ? 'Enabled' : 'Disabled'}`, 'info');
    });
  }

  const qrUrlEl = document.getElementById('mobileStudioQRUrl');
  if (qrUrlEl) {
    qrUrlEl.addEventListener('click', () => {
      if (mobileQrUrl) {
        navigator.clipboard.writeText(mobileQrUrl).then(() => {
          qrUrlEl.style.color = 'var(--success)';
          setTimeout(() => { qrUrlEl.style.color = ''; }, 1200);
          showToast('Copied Mobile URL to clipboard', 'info');
        });
      }
    });
  }

  // Start polling for mobile customer uploads every 2 seconds
  if (mobilePollTimer) clearInterval(mobilePollTimer);
  mobilePollTimer = setInterval(pollMobileUploads, 2000);
  pollMobileUploads();
}

async function pollMobileUploads() {
  try {
    const res = await fetch('/api/mobile-photos');
    if (!res.ok) return;
    const data = await res.json();
    if (!data || !Array.isArray(data.files)) return;

    // Process from oldest to newest
    const sorted = [...data.files].sort((a, b) => new Date(a.timestamp) - new Date(b.timestamp));
    let newArrivedCount = 0;

    for (const f of sorted) {
      if (!knownMobileFiles.has(f.filePath)) {
        knownMobileFiles.add(f.filePath);
        newArrivedCount++;
        handleIncomingMobilePhoto(f);
      }
    }

    // Update badge numbers
    mobileReceivedCount = knownMobileFiles.size;
    const livePill = document.getElementById('mobileLivePill');
    if (livePill) livePill.textContent = `${mobileReceivedCount} Received`;

    const headerBadge = document.getElementById('headerMobileCountBadge');
    if (headerBadge) {
      headerBadge.textContent = mobileReceivedCount;
      headerBadge.style.display = mobileReceivedCount > 0 ? 'inline-block' : 'none';
    }

    const modalCount = document.getElementById('mobileModalCount');
    if (modalCount) modalCount.textContent = mobileReceivedCount;

  } catch (err) {}
}

function handleIncomingMobilePhoto(f) {
  // Add item to Modal list
  const listEl = document.getElementById('mobileModalPhotosList');
  const emptyEl = document.getElementById('mobileModalEmptyMsg');
  if (emptyEl) emptyEl.style.display = 'none';

  if (listEl) {
    const itemEl = document.createElement('div');
    itemEl.style.cssText = 'display:flex;align-items:center;gap:8px;background:rgba(0,0,0,0.35);padding:6px 10px;border-radius:6px;border:1px solid rgba(255,255,255,0.06);';
    const timeStr = f.timestamp ? new Date(f.timestamp).toLocaleTimeString() : '';
    const sizeStr = formatBytes(f.fileSize || 0);

    itemEl.innerHTML = `
      <i class="fa-solid fa-mobile-screen" style="color: #06b6d4; font-size: 1.1rem;"></i>
      <div style="flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">
        <strong style="color: var(--text-primary); font-family: monospace; font-size: 0.8rem;">${escapeHtml(f.fileName)}</strong>
        <div style="font-size: 0.65rem; color: var(--text-muted);">${timeStr} · ${sizeStr} · Qty: ${f.qty || 1}</div>
      </div>
      <button class="btn btn-xs btn-primary" onclick="loadSingleMobilePhoto('${escapeHtml(f.filePath)}','${escapeHtml(f.fileName)}','${escapeHtml(f.url)}',${f.fileSize || 0},${f.qty || 1})" style="padding:2px 8px; font-size:0.7rem;">
        Load
      </button>
    `;
    listEl.insertBefore(itemEl, listEl.firstChild);
  }

  // If in Studio Pro mode and Auto-Ingest is active:
  if (mobileAutoIngest) {
    loadSingleMobilePhoto(f.filePath, f.fileName, f.url, f.fileSize, f.qty);
  }
}

function loadSingleMobilePhoto(filePath, fileName, url, fileSize, qty) {
  // Check if already in filesQueue
  const exists = filesQueue.some(i => i.path === filePath);
  if (exists) return;

  const newItem = {
    id: 'mob_' + Date.now() + '_' + Math.random().toString(36).substring(2, 6),
    name: fileName,
    file: null,
    handle: null,
    path: filePath,
    url: url,
    sizeStr: formatBytes(fileSize || 0),
    checked: true,
    passed: false,
    qty: qty || 1,
    printMode: 'overall',
    manualCropEdited: false,
    crop: { x: 0, y: 0, w: 1, h: 1 },
    isCropped: false,
    editParams: getDefaultEditParams(),
    dateModified: new Date(),
    isMobileUpload: true
  };

  // Prepend so newest mobile photo appears first in Studio filmstrip
  filesQueue.unshift(newItem);
  renderSourceExplorer();
  updateGrid();
  updateUIState();

  if (!activeItem) {
    activeItem = newItem;
    syncSidebarToActiveItem();
  }

  addLog(`[Mobile Customer] Loaded ${fileName} (Qty: ${qty || 1}) into Studio Pro queue`, 'success');
  showToast(`📱 Mobile photo received: ${fileName}`, 'success');
}

async function importAllMobileToStudio() {
  try {
    const res = await fetch('/api/mobile-photos');
    if (!res.ok) return;
    const data = await res.json();
    if (!data || !Array.isArray(data.files)) return;

    let loaded = 0;
    for (const f of data.files) {
      if (!filesQueue.some(i => i.path === f.filePath)) {
        loadSingleMobilePhoto(f.filePath, f.fileName, f.url, f.fileSize, f.qty);
        loaded++;
      }
    }
    showToast(`Loaded ${loaded} mobile photo(s) into Studio Pro`, 'success');
  } catch (err) {
    showToast('Failed to import mobile photos: ' + err.message, 'error');
  }
}

async function openMobileStudioModal() {
  const modal = document.getElementById('mobileStudioModal');
  if (!modal) return;
  modal.style.display = 'flex';

  try {
    const resp = await fetch('/api/info');
    const info = await resp.json();
    const ip = info.ip || '127.0.0.1';
    const port = info.port || 8080;
    mobileQrUrl = `http://${ip}:${port}/customer`;
    mobileWifiSsid = info.wifiSsid || 'Wi-Fi Network / Hotspot';

    const urlEl = document.getElementById('mobileStudioQRUrl');
    if (urlEl) urlEl.textContent = mobileQrUrl;

    const wifiEl = document.getElementById('mobileWifiNameDisplay');
    if (wifiEl) wifiEl.textContent = mobileWifiSsid;

    const container = document.getElementById('mobileStudioQRContainer');
    if (container) {
      container.innerHTML = '';
      if (typeof QRCode !== 'undefined') {
        mobileStudioQRInstance = new QRCode(container, {
          text: mobileQrUrl,
          width: 180,
          height: 180,
          colorDark: '#000000',
          colorLight: '#ffffff',
          correctLevel: QRCode.CorrectLevel.M
        });
      } else {
        container.innerHTML = '<div style="color:#64748b;font-size:0.75rem;text-align:center;">QR Generator Ready<br>' + escapeHtml(mobileQrUrl) + '</div>';
      }
    }
  } catch (err) {
    console.error('Failed to get mobile info', err);
  }

  pollMobileUploads();
}

function closeMobileStudioModal() {
  const modal = document.getElementById('mobileStudioModal');
  if (modal) modal.style.display = 'none';
}

async function selectSourceFolder() {
  // Primary: Trigger direct native Windows directory picker via HTML5 input
  if (els.sourceDirInput) {
    els.sourceDirInput.value = '';
    els.sourceDirInput.click();
    return;
  }
  
  if (els.fileSelector) {
    els.fileSelector.webkitdirectory = true;
    els.fileSelector.click();
  }
}

function handleSourceDirChange(e) {
  const allFiles = Array.from(e.target.files);
  const files = allFiles.filter(f => /\.(jpe?g|png|webp|bmp)$/i.test(f.name));
  if (files.length === 0) {
    showToast('No image files found in the selected folder', 'warning');
    return;
  }

  let folderName = 'Selected Folder';
  if (files[0].webkitRelativePath) {
    folderName = files[0].webkitRelativePath.split('/')[0] || files[0].webkitRelativePath.split('\\')[0] || folderName;
  }
  sourceFolderPath = folderName;
  if (els.sourcePathDisplay) {
    els.sourcePathDisplay.textContent = folderName;
    els.sourcePathDisplay.classList.add('active');
  }

  loadSourcePhotoFiles(files, folderName);
}

function loadSourcePhotoFiles(files, folderName) {
  const newItems = files.map(file => ({
    name: file.name,
    file: file,
    url: null,
    sizeStr: formatBytes(file.size),
    checked: true,
    passed: false,
    qty: 1,
    status: 'ready',
    crop: { x: 0, y: 0, w: 1, h: 1 },
    manualCropEdited: false,
    isCropped: false,
    isEdited: false,
    printMode: 'cut',
    editParams: getDefaultEditParams(),
    originalImageObject: null
  }));

  filesQueue = newItems;
  gridPage = 0;
  activeItem = filesQueue[0] || null;

  addLog(`[Source] Loaded ${filesQueue.length} photos from: ${folderName}`, 'success');
  showToast(`Loaded ${filesQueue.length} photos`, 'success');

  renderSourceExplorer();
  updateSelectionCounts();
  updateGrid();
  updateUIState();
  syncSidebarToActiveItem();

  newItems.forEach(item => {
    const url = URL.createObjectURL(item.file);
    const img = new Image();
    img.onload = () => {
      item.originalImageObject = img;
      if (item.printMode === 'cut') {
        const targetRatio = getChannelRatio(img.naturalWidth, img.naturalHeight, activeChannel);
        item.crop = getDefaultCropForRatio(img.naturalWidth, img.naturalHeight, targetRatio);
        item.isCropped = true;
      }
      URL.revokeObjectURL(url);
      updateGrid();
    };
    img.src = url;
  });
}

async function loadPhotosFromDirectory(dirPath) {
  try {
    const res = await fetch('/api/list-folder', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ folder: dirPath })
    });
    const data = await res.json();
    if (data.files && data.files.length > 0) {
      const newItems = data.files.map(f => ({
        name: f.name,
        path: f.path,
        url: f.url,
        file: null,
        sizeStr: formatBytes(f.size),
        status: 'ready',
        checked: true,
        qty: 1,
        crop: { x: 0, y: 0, w: 1, h: 1 },
        isCropped: false,
        isEdited: false,
        printMode: 'cut',
        editParams: getDefaultEditParams(),
        originalImageObject: null
      }));

      filesQueue = newItems;
      gridPage = 0;
      activeItem = filesQueue[0] || null;
      addLog(`[Source] Loaded ${filesQueue.length} photos from: ${dirPath}`, 'success');
      showToast(`Loaded ${filesQueue.length} photos`, 'success');
      
      renderSourceExplorer();
      updateGrid();
      updateUIState();
    } else {
      showToast(`No photos found in selected folder`, 'warning');
      addLog(`No image files found in ${dirPath}`, 'warning');
    }
  } catch (err) {
    addLog(`Error loading photos from folder: ${err.message}`, 'error');
  }
}

// Windows Explorer File Selection & List Renderer
function renderSourceExplorer() {
  if (!els.sourceFileList) return;
  const filter = (els.sourceSearchInput && els.sourceSearchInput.value) ? els.sourceSearchInput.value.toLowerCase() : '';
  const filtered = filesQueue.filter(item => !filter || item.name.toLowerCase().includes(filter));
  const checkedCount = filesQueue.filter(item => item.checked && !item.passed).length;
  const passedCount = filesQueue.filter(item => item.checked && item.passed).length;
  
  if (els.sourceCountBadge) els.sourceCountBadge.textContent = `${filesQueue.length} photos`;
  if (els.selectedCountDisplay) {
    if (passedCount > 0) {
      els.selectedCountDisplay.textContent = `${checkedCount} selected (${passedCount} passed)`;
    } else {
      els.selectedCountDisplay.textContent = `${checkedCount} selected`;
    }
  }

  if (filesQueue.length === 0) {
    els.sourceFileList.innerHTML = `
      <div class="source-empty-msg">
        <i class="fa-solid fa-folder-open" style="font-size: 1.5rem; opacity: 0.4; margin-bottom: 0.3rem;"></i><br>
        <span>Click "Select Folder" or "Files" at any time to load photos</span>
      </div>
    `;
    return;
  }

  els.sourceFileList.innerHTML = '';
  filtered.forEach((item) => {
    const originalIndex = filesQueue.indexOf(item);
    const row = document.createElement('div');
    row.className = `source-file-row ${item.checked ? 'selected' : ''} ${item.passed ? 'passed' : ''} ${activeItem && activeItem.name === item.name ? 'active-item' : ''}`;
    row.dataset.index = originalIndex;

    const chk = document.createElement('input');
    chk.type = 'checkbox';
    chk.className = 'source-file-checkbox';
    chk.checked = !!item.checked;
    chk.onclick = (e) => {
      e.stopPropagation();
      item.checked = chk.checked;
      row.classList.toggle('selected', item.checked);
      lastSelectedExplorerIndex = originalIndex;
      updateSelectionCounts();
      updateGrid();
    };

    const icon = document.createElement('i');
    icon.className = item.passed ? 'fa-solid fa-circle-xmark' : 'fa-solid fa-image';
    icon.style.fontSize = '0.75rem';
    icon.style.color = item.passed ? '#ef4444' : (item.checked ? 'var(--primary)' : 'var(--text-muted)');

    const info = document.createElement('div');
    info.className = 'source-file-info';

    const name = document.createElement('div');
    name.className = 'source-file-name';
    name.textContent = item.name + (item.passed ? ' [PASSED]' : '');
    name.title = item.name;

    const meta = document.createElement('div');
    meta.className = 'source-file-meta';
    meta.textContent = `${item.sizeStr || ''} • Qty: ${item.qty || 1}${item.passed ? ' • SKIP' : ''}`;

    info.appendChild(name);
    info.appendChild(meta);

    row.appendChild(chk);
    row.appendChild(icon);
    row.appendChild(info);

    // Windows Explorer gestures: Click, Shift+Click, Ctrl+Click
    row.onclick = (e) => {
      if (e.shiftKey && lastSelectedExplorerIndex !== -1) {
        // Continuous range selection
        const start = Math.min(lastSelectedExplorerIndex, originalIndex);
        const end = Math.max(lastSelectedExplorerIndex, originalIndex);
        for (let k = start; k <= end; k++) {
          filesQueue[k].checked = true;
        }
      } else if (e.ctrlKey || e.metaKey) {
        // Multi-select toggle
        item.checked = !item.checked;
        lastSelectedExplorerIndex = originalIndex;
      } else {
        // Single selection
        item.checked = !item.checked;
        lastSelectedExplorerIndex = originalIndex;
      }
      activeItem = item;
      syncSidebarToActiveItem();
      renderSourceExplorer();
      updateGrid();
    };

    els.sourceFileList.appendChild(row);
  });
}

function updateSelectionCounts() {
  const checkedCount = filesQueue.filter(item => item.checked && !item.passed).length;
  const passedCount = filesQueue.filter(item => item.checked && item.passed).length;
  if (els.selectedCountDisplay) {
    if (passedCount > 0) {
      els.selectedCountDisplay.textContent = `${checkedCount} selected (${passedCount} passed)`;
    } else {
      els.selectedCountDisplay.textContent = `${checkedCount} selected`;
    }
  }
  if (els.btnStartProcess) {
    if (checkedCount > 0 && !isProcessing) {
      els.btnStartProcess.disabled = false;
      els.btnStartProcess.classList.remove('btn-disabled');
      els.btnStartProcess.innerHTML = `<i class="fa-solid fa-play"></i> Start Processing (${checkedCount})`;
    } else if (!isProcessing) {
      els.btnStartProcess.disabled = true;
      els.btnStartProcess.classList.add('btn-disabled');
      els.btnStartProcess.innerHTML = `<i class="fa-solid fa-play"></i> Start Processing`;
    }
  }
}

function toggleAllExplorerItems(selectState) {
  filesQueue.forEach(item => item.checked = selectState);
  renderSourceExplorer();
  updateGrid();
  updateSelectionCounts();
}

async function browseFiles() {
  try {
    if (window.showOpenFilePicker) {
      const handles = await window.showOpenFilePicker({
        multiple: true,
        types: [{
          description: 'Image Files',
          accept: {
            'image/*': ['.jpg', '.jpeg', '.png', '.webp', '.bmp']
          }
        }]
      });
      if (handles && handles.length > 0) {
        await loadFileHandles(handles);
      }
    } else {
      if (els.fileSelector) {
        els.fileSelector.webkitdirectory = false;
        els.fileSelector.click();
      }
    }
  } catch (err) {
    if (err.name !== 'AbortError') {
      addLog(`Error selecting files: ${err.message}`, 'error');
      showToast('Failed to select files.', 'error');
    }
  }
}

function handleFileSelectorChange(e) {
  const files = Array.from(e.target.files);
  if (files.length > 0) {
    loadFileObjects(files);
  }
}

async function loadFileHandles(handles) {
  const newItems = [];
  for (const handle of handles) {
    if (filesQueue.some(item => item.name === handle.name)) continue;
    
    newItems.push({
      name: handle.name,
      handle: handle,
      status: 'pending',
      file: null,
      sizeStr: 'Loading...',
      checked: true,
      qty: 1,
      thumbnailUrl: null,
      crop: { x: 0, y: 0, w: 1, h: 1 },
      manualCropEdited: false,
      isCropped: false,
      isEdited: false,
      printMode: 'cut', // Default to cut mode
      editParams: getDefaultEditParams(),
      originalImageObject: null
    });
  }
  
  if (newItems.length === 0) return;
  
  filesQueue = [...filesQueue, ...newItems];
  if (els.inputPathDisplay) {
    els.inputPathDisplay.textContent = `${filesQueue.length} files`;
    els.inputPathDisplay.classList.add('active');
  }
  addLog(`Loaded ${newItems.length} photos. Total: ${filesQueue.length}`, 'info');
  renderSourceExplorer();
  updateSelectionCounts();
  renderQueue();
  updateUIState();
  
  if (!activeItem && filesQueue.length > 0) {
    activeItem = filesQueue[0];
    syncSidebarToActiveItem();
  }
  
  updateGrid();
  
  // Calculate size and pre-cache original image object
  newItems.forEach(async (item) => {
    try {
      const file = await item.handle.getFile();
      item.file = file;
      item.sizeStr = formatBytes(file.size);
      
      const safeId = item.name.replace(/\s+/g, '-');
      const sizeEl = document.getElementById(`size-${safeId}`);
      if (sizeEl) sizeEl.textContent = item.sizeStr;
      
      const url = URL.createObjectURL(file);
      const img = new Image();
      img.onload = () => {
        item.originalImageObject = img;
        
        // Auto pre-crop according to the active channel in Cut mode
        if (item.printMode === 'cut') {
          const targetRatio = getChannelRatio(img.naturalWidth, img.naturalHeight, activeChannel);
          item.crop = getDefaultCropForRatio(img.naturalWidth, img.naturalHeight, targetRatio);
          item.isCropped = true;
        }
        
        URL.revokeObjectURL(url);
        updateGrid();
      };
      img.src = url;
      
    } catch (e) {
      item.sizeStr = 'Unknown';
    }
  });
}

function loadFileObjects(files) {
  const newItems = [];
  for (const file of files) {
    if (filesQueue.some(item => item.name === file.name)) continue;
    
    newItems.push({
      name: file.name,
      handle: null,
      status: 'pending',
      file: file,
      sizeStr: formatBytes(file.size),
      checked: true,
      qty: 1,
      thumbnailUrl: null,
      crop: { x: 0, y: 0, w: 1, h: 1 },
      manualCropEdited: false,
      isCropped: false,
      isEdited: false,
      printMode: 'cut', // Default to cut mode
      editParams: getDefaultEditParams(),
      originalImageObject: null
    });
  }
  
  if (newItems.length === 0) return;
  
  filesQueue = [...filesQueue, ...newItems];
  if (els.inputPathDisplay) {
    els.inputPathDisplay.textContent = `${filesQueue.length} files`;
    els.inputPathDisplay.classList.add('active');
  }
  addLog(`Loaded ${newItems.length} photos. Total: ${filesQueue.length}`, 'info');
  showToast(`Loaded ${newItems.length} photos`, 'success');
  
  renderSourceExplorer();
  updateSelectionCounts();
  renderQueue();
  updateUIState();
  
  if (!activeItem && filesQueue.length > 0) {
    activeItem = filesQueue[0];
    syncSidebarToActiveItem();
  }
  
  updateGrid();
  
  newItems.forEach(async (item) => {
    const url = URL.createObjectURL(item.file);
    const img = new Image();
    img.onload = () => {
      item.originalImageObject = img;
      
      if (item.printMode === 'cut') {
        const targetRatio = getChannelRatio(img.naturalWidth, img.naturalHeight, activeChannel);
        item.crop = getDefaultCropForRatio(img.naturalWidth, img.naturalHeight, targetRatio);
        item.isCropped = true;
      }
      
      URL.revokeObjectURL(url);
      updateGrid();
    };
    img.src = url;
  });
}

function clearQueue() {
  if (isProcessing) return;
  filesQueue = [];
  activeItem = null;
  gridPage = 0;
  sourceFolderPath = '';
  if (els.sourcePathDisplay) {
    els.sourcePathDisplay.textContent = 'Dynamic Selection (Choose folder at any time)';
    els.sourcePathDisplay.classList.remove('active');
  }
  if (els.sourceCountBadge) els.sourceCountBadge.textContent = '0 photos';
  if (els.inputPathDisplay) {
    els.inputPathDisplay.textContent = "0 photos selected";
    els.inputPathDisplay.classList.remove('active');
  }
  if (els.fileSelector) els.fileSelector.value = '';
  if (els.sourceDirInput) els.sourceDirInput.value = '';
  addLog('Photo queue cleared.', 'warning');
  showToast('Queue cleared', 'info');
  
  renderSourceExplorer();
  updateSelectionCounts();
  renderQueue();
  updateUIState();
  syncSidebarToActiveItem();
  updateGrid();
}


async function selectFolderArchive() {
  try {
    archiveDirHandle = await window.showDirectoryPicker({ mode: 'readwrite' });
    els.archivePathDisplay.textContent = archiveDirHandle.name;
    els.archivePathDisplay.classList.add('active');
    addLog(`Archive folder selected: ${archiveDirHandle.name}`, 'info');
    showToast(`Folder selected: ${archiveDirHandle.name}`, 'success');
    updateUIState();
  } catch (err) {
    if (err.name !== 'AbortError') {
      addLog(`Error selecting archive folder: ${err.message}`, 'error');
      showToast('Failed to open archive folder.', 'error');
    }
  }
}

// ----------------------------------------------------
// UI Sync & Grid Paging
// ----------------------------------------------------
function syncSidebarToActiveItem() {
  if (!activeItem) {
    if (els.activeEditBadge) {
      els.activeEditBadge.textContent = "No Photo Selected to Edit";
      els.activeEditBadge.style.background = "rgba(255, 255, 255, 0.02)";
      els.activeEditBadge.style.color = "var(--text-secondary)";
    }
    if (els.btnToggleViewMode) els.btnToggleViewMode.style.display = 'none';
    disableEditSliders(true);
    updateCMYDDisplay();
    return;
  }
  
  disableEditSliders(false);
  if (els.btnToggleViewMode) els.btnToggleViewMode.style.display = 'block';
  if (els.activeEditBadge) {
    els.activeEditBadge.textContent = `Editing: ${activeItem.name}`;
    els.activeEditBadge.style.background = "rgba(6, 182, 212, 0.1)";
    els.activeEditBadge.style.color = "var(--primary)";
  }
  
  const ep = activeItem.editParams;
  if (els.chkColorCorrection) els.chkColorCorrection.checked = ep.chkColorCorrection;
  if (els.correctionAlgorithm) els.correctionAlgorithm.value = ep.correctionAlgorithm;
  
  if (ep.chkColorCorrection) {
    if (els.colorCorrectionParams) els.colorCorrectionParams.style.display = 'flex';
    if (els.previewRightLabel) els.previewRightLabel.textContent = "Color Corrected";
  } else {
    if (els.colorCorrectionParams) els.colorCorrectionParams.style.display = 'none';
    if (els.previewRightLabel) els.previewRightLabel.textContent = "Watermarked";
  }
  
  updateCMYDDisplay();
  
  if (els.paramContrast) {
    els.paramContrast.value = ep.paramContrast;
    els.contrastValue.textContent = `${ep.paramContrast > 0 ? '+' : ''}${ep.paramContrast}%`;
  }
  if (els.paramSaturation) {
    els.paramSaturation.value = ep.paramSaturation;
    els.saturationValue.textContent = `${ep.paramSaturation > 0 ? '+' : ''}${ep.paramSaturation}%`;
  }
  
  // Highlight active frame in grid
  const startIdx = gridPage * 6;
  for (let i = 0; i < 6; i++) {
    const frameEl = document.getElementById(`frame-${i + 1}`);
    const itemIdx = startIdx + i;
    if (frameEl) {
      if (itemIdx < filesQueue.length && filesQueue[itemIdx].name === activeItem.name) {
        frameEl.classList.add('active');
      } else {
        frameEl.classList.remove('active');
      }
    }
  }
}

function disableEditSliders(disableState) {
  const inputs = [
    els.chkColorCorrection, els.correctionAlgorithm, 
    els.btnCUp, els.btnCDown, els.btnMUp, els.btnMDown,
    els.btnYUp, els.btnYDown, els.btnDUp, els.btnDDown,
    els.paramContrast, els.paramSaturation
  ];
  inputs.forEach(input => {
    if (input) {
      if (disableState) {
        input.setAttribute('disabled', 'true');
      } else {
        input.removeAttribute('disabled');
      }
    }
  });
}

function navigateGridPage(dir) {
  const selectedFiles = filesQueue.filter(item => item.checked);
  const totalPages = Math.ceil(selectedFiles.length / 6) || 1;
  gridPage = Math.max(0, Math.min(totalPages - 1, gridPage + dir));
  updateGrid();
}

function updateUIState() {
  const checkedCount = filesQueue.filter(item => item.checked && !item.passed).length;
  const hasCheckedQueue = checkedCount > 0;
  
  if (els.btnStartProcess) {
    if (hasCheckedQueue && !isProcessing) {
      els.btnStartProcess.disabled = false;
      els.btnStartProcess.classList.remove('btn-disabled');
      els.btnStartProcess.innerHTML = `<i class="fa-solid fa-play"></i> Start Processing (${checkedCount})`;
    } else {
      els.btnStartProcess.disabled = true;
      els.btnStartProcess.classList.add('btn-disabled');
      els.btnStartProcess.innerHTML = `<i class="fa-solid fa-play"></i> Start Processing`;
    }
  }

  if (isProcessing) {
    if (els.btnPauseProcess) els.btnPauseProcess.classList.remove('btn-disabled');
    if (els.btnBrowseFiles) els.btnBrowseFiles.classList.add('btn-disabled');
    if (els.btnClearQueue) els.btnClearQueue.classList.add('btn-disabled');
    if (els.btnSelectArchive) els.btnSelectArchive.classList.add('btn-disabled');
    if (els.templateInput) els.templateInput.setAttribute('disabled', 'true');
    if (els.btnRemoveTemplate) els.btnRemoveTemplate.classList.add('btn-disabled');
    if (els.btnSelectAll) els.btnSelectAll.classList.add('btn-disabled');
    if (els.btnDeselectAll) els.btnDeselectAll.classList.add('btn-disabled');
    if (els.btnPrintPageAll) els.btnPrintPageAll.classList.add('btn-disabled');
  } else {
    if (els.btnPauseProcess) els.btnPauseProcess.classList.add('btn-disabled');
    if (els.btnBrowseFiles) els.btnBrowseFiles.classList.remove('btn-disabled');
    if (els.btnClearQueue) els.btnClearQueue.classList.remove('btn-disabled');
    if (els.btnSelectArchive) els.btnSelectArchive.classList.remove('btn-disabled');
    if (els.templateInput) els.templateInput.removeAttribute('disabled');
    if (els.btnRemoveTemplate) els.btnRemoveTemplate.classList.remove('btn-disabled');
    if (els.btnSelectAll) els.btnSelectAll.classList.remove('btn-disabled');
    if (els.btnDeselectAll) els.btnDeselectAll.classList.remove('btn-disabled');
    
    const checked = filesQueue.filter(item => item.checked).length;
    if (els.btnPrintPageAll) els.btnPrintPageAll.disabled = (filesQueue.length === 0 || checked === 0);
  }
}

// ----------------------------------------------------
// 6-Frame Preview Rendering
// ----------------------------------------------------
async function updateGrid() {
  const selectedFiles = filesQueue.filter(item => item.checked);
  const totalPages = Math.ceil(selectedFiles.length / 6) || 1;
  if (gridPage >= totalPages) gridPage = Math.max(0, totalPages - 1);
  const startIdx = gridPage * 6;
  
  els.gridPageIndicator.textContent = `Page ${gridPage + 1} of ${totalPages} (${selectedFiles.length} selected)`;
  els.btnPrevPage.disabled = (gridPage === 0);
  els.btnNextPage.disabled = (gridPage >= totalPages - 1);
  
  const pageCheckedCount = selectedFiles.slice(startIdx, startIdx + 6).filter(item => !item.passed).length;
  if (els.btnPrintPageAll) els.btnPrintPageAll.disabled = (selectedFiles.length === 0 || pageCheckedCount === 0);
  
  for (let i = 0; i < 6; i++) {
    const frameId = i + 1;
    const item = selectedFiles[startIdx + i];
    
    const frameEl = document.getElementById(`frame-${frameId}`);
    if (!frameEl) continue;
    const canvas = document.getElementById(`frameCanvas-${frameId}`);
    const placeholder = frameEl.querySelector('.frame-placeholder');
    const filenameEl = frameEl.querySelector('.frame-filename');
    const badgeEl = frameEl.querySelector('.frame-badge');
    const qtyInput = frameEl.querySelector('.frame-qty-input');
    const btnQtyMinus = frameEl.querySelector('.btn-qty-minus');
    const btnQtyPlus = frameEl.querySelector('.btn-qty-plus');
    const btnEdit = frameEl.querySelector('.btn-frame-edit');
    const btnCrop = frameEl.querySelector('.btn-frame-crop');
    const btnPrint = frameEl.querySelector('.btn-frame-print');
    
    // Fit toggles inside each frame card
    const btnCut = frameEl.querySelector('.btn-mode-cut');
    const btnOverall = frameEl.querySelector('.btn-mode-overall');
    
    if (item) {
      
      // Update metadata
      if (filenameEl) {
        filenameEl.textContent = item.name;
        filenameEl.title = item.name;
      }
      
      if (badgeEl) {
        badgeEl.className = 'frame-badge';
        if (item.passed) {
          badgeEl.textContent = 'PASSED';
          badgeEl.classList.add('status-passed');
        } else if (item.status === 'completed') {
          badgeEl.textContent = 'Printed';
          badgeEl.classList.add('status-completed');
        } else if (item.status === 'processing') {
          badgeEl.textContent = 'Printing';
          badgeEl.classList.add('status-processing');
        } else if (item.status === 'failed') {
          badgeEl.textContent = 'Error';
          badgeEl.classList.add('status-failed');
        } else {
          badgeEl.textContent = 'Ready';
          badgeEl.classList.add('status-loaded');
        }
      }
      
      frameEl.classList.toggle('frame-passed', !!item.passed);
      if (activeItem && activeItem.name === item.name) {
        frameEl.classList.add('active');
      } else {
        frameEl.classList.remove('active');
      }
      
      // Quantity controls
      if (qtyInput) {
        qtyInput.removeAttribute('disabled');
        qtyInput.value = item.qty || 1;
        qtyInput.onchange = (e) => {
          let val = parseInt(e.target.value);
          if (isNaN(val) || val < 1) val = 1;
          item.qty = val;
          e.target.value = val;
          renderSourceExplorer();
        };
      }
      if (btnQtyMinus) {
        btnQtyMinus.removeAttribute('disabled');
        btnQtyMinus.onclick = (e) => {
          e.stopPropagation();
          let val = Math.max(1, (item.qty || 1) - 1);
          item.qty = val;
          if (qtyInput) qtyInput.value = val;
          renderSourceExplorer();
        };
      }
      if (btnQtyPlus) {
        btnQtyPlus.removeAttribute('disabled');
        btnQtyPlus.onclick = (e) => {
          e.stopPropagation();
          let val = Math.min(99, (item.qty || 1) + 1);
          item.qty = val;
          if (qtyInput) qtyInput.value = val;
          renderSourceExplorer();
        };
      }

      if (btnEdit) {
        btnEdit.removeAttribute('disabled');
        btnEdit.onclick = (e) => {
          e.stopPropagation();
          activeItem = item;
          switchToDetailView(false);
        };
      }
      if (btnCrop) {
        btnCrop.removeAttribute('disabled');
        btnCrop.onclick = (e) => {
          e.stopPropagation();
          activeItem = item;
          switchToDetailView(true);
        };
      }
      if (btnPrint) {
        btnPrint.removeAttribute('disabled');
        btnPrint.onclick = (e) => {
          e.stopPropagation();
          printImage(item);
        };
      }
      
      // Setup fit mode buttons
      if (btnCut) {
        btnCut.removeAttribute('disabled');
        if (item.printMode === 'cut') btnCut.classList.add('active');
        else btnCut.classList.remove('active');
        btnCut.onclick = (e) => {
          e.stopPropagation();
          setPrintMode(item, 'cut');
        };
      }
      if (btnOverall) {
        btnOverall.removeAttribute('disabled');
        if (item.printMode !== 'cut') btnOverall.classList.add('active');
        else btnOverall.classList.remove('active');
        btnOverall.onclick = (e) => {
          e.stopPropagation();
          setPrintMode(item, 'overall');
        };
      }
      
      if (canvas) canvas.style.display = 'block';
      if (placeholder) placeholder.style.display = 'none';
      
      if (canvas) renderFrameThumbnail(item, canvas);
      
      // Wire up per-frame CMYD correction buttons
      const cmydPanel = frameEl.querySelector('.frame-cmyd-panel');
      if (cmydPanel) {
        const cmydBtns = cmydPanel.querySelectorAll('.cmyd-btn');
        cmydBtns.forEach(btn => {
          btn.removeAttribute('disabled');
          btn.onclick = (e) => {
            e.stopPropagation();
            const paramName = btn.dataset.param;
            const dir = btn.classList.contains('cmyd-up') ? 1 : -1;
            if (!item.editParams[paramName] && item.editParams[paramName] !== 0) {
              item.editParams[paramName] = 0;
            }
            item.editParams[paramName] = Math.max(-20, Math.min(20, item.editParams[paramName] + dir));
            // Update the value display (the span between the two buttons)
            const numEl = btn.classList.contains('cmyd-up') ? btn.nextElementSibling : btn.previousElementSibling;
            if (numEl && numEl.classList.contains('cmyd-num')) {
              const val = item.editParams[paramName];
              numEl.textContent = val > 0 ? '+' + val : String(val);
              numEl.classList.toggle('nonzero', val !== 0);
            }
            if (canvas) renderFrameThumbnail(item, canvas);
            if (activeItem === item) syncSidebarToActiveItem();
          };
        });

        // Wire up CMYD reset '0' button
        const resetBtn = cmydPanel.querySelector('.cmyd-reset-btn');
        if (resetBtn) {
          resetBtn.removeAttribute('disabled');
          resetBtn.onclick = (e) => {
            e.stopPropagation();
            item.editParams.paramC = 0;
            item.editParams.paramM = 0;
            item.editParams.paramY = 0;
            item.editParams.paramD = 0;
            const numEls = cmydPanel.querySelectorAll('.cmyd-num');
            numEls.forEach(el => {
              el.textContent = '0';
              el.classList.remove('nonzero');
            });
            if (canvas) renderFrameThumbnail(item, canvas);
            if (activeItem === item) syncSidebarToActiveItem();
          };
        }

        // Sync display values from current item state (C, M, Y, D only now)
        const numEls = cmydPanel.querySelectorAll('.cmyd-num');
        const params = ['paramC', 'paramM', 'paramY', 'paramD'];
        numEls.forEach((el, idx) => {
          if (idx < params.length) {
            const val = item.editParams[params[idx]] || 0;
            el.textContent = val > 0 ? '+' + val : String(val);
            el.classList.toggle('nonzero', val !== 0);
          }
        });
      }
      
      const frameBody = frameEl.querySelector('.frame-body');
      if (frameBody) {
        frameBody.onclick = () => {
          activeItem = item;
          syncSidebarToActiveItem();
          renderSourceExplorer();
        };
      }

      // Double-click to inspect in Single-Frame Mode
      frameEl.ondblclick = (e) => {
        e.preventDefault();
        e.stopPropagation();
        activeItem = item;
        switchToDetailView(false);
      };

      // Right-click on frame to Pass (skip) or un-pass
      frameEl.oncontextmenu = (e) => {
        e.preventDefault();
        e.stopPropagation();
        item.passed = !item.passed;
        frameEl.classList.toggle('frame-passed', !!item.passed);
        if (badgeEl) {
          if (item.passed) {
            badgeEl.className = 'frame-badge status-passed';
            badgeEl.textContent = 'PASSED';
          } else {
            badgeEl.className = 'frame-badge status-loaded';
            badgeEl.textContent = 'Ready';
          }
        }
        renderSourceExplorer();
        updateSelectionCounts();
        if (item.passed) {
          showToast(`Frame #${frameId} (${item.name}) marked as PASSED (skipped)`, 'info');
        } else {
          showToast(`Frame #${frameId} (${item.name}) RESTORED`, 'success');
        }
      };
      
    } else {
      // Empty slot
      if (filenameEl) {
        filenameEl.textContent = 'Empty Slot';
        filenameEl.title = '';
      }
      if (badgeEl) {
        badgeEl.className = 'frame-badge status-empty';
        badgeEl.textContent = 'Empty';
      }
      
      frameEl.classList.remove('active');
      frameEl.classList.remove('frame-passed');
      frameEl.ondblclick = null;
      frameEl.oncontextmenu = (e) => e.preventDefault();
      if (qtyInput) {
        qtyInput.setAttribute('disabled', 'true');
        qtyInput.value = 1;
        qtyInput.onchange = null;
      }
      if (btnQtyMinus) {
        btnQtyMinus.setAttribute('disabled', 'true');
        btnQtyMinus.onclick = null;
      }
      if (btnQtyPlus) {
        btnQtyPlus.setAttribute('disabled', 'true');
        btnQtyPlus.onclick = null;
      }
      if (btnEdit) {
        btnEdit.setAttribute('disabled', 'true');
        btnEdit.onclick = null;
      }
      if (btnCrop) {
        btnCrop.setAttribute('disabled', 'true');
        btnCrop.onclick = null;
      }
      if (btnPrint) {
        btnPrint.setAttribute('disabled', 'true');
        btnPrint.onclick = null;
      }
      
      if (btnCut) {
        btnCut.setAttribute('disabled', 'true');
        btnCut.classList.remove('active');
        btnCut.onclick = null;
      }
      if (btnOverall) {
        btnOverall.setAttribute('disabled', 'true');
        btnOverall.classList.remove('active');
        btnOverall.onclick = null;
      }
      
      // Disable and reset CMYD panel
      const cmydPanel = frameEl.querySelector('.frame-cmyd-panel');
      if (cmydPanel) {
        cmydPanel.querySelectorAll('.cmyd-btn').forEach(btn => {
          btn.setAttribute('disabled', 'true');
          btn.onclick = null;
        });
        cmydPanel.querySelectorAll('.cmyd-num').forEach(el => {
          el.textContent = '0';
          el.classList.remove('nonzero');
        });
        const resetBtn = cmydPanel.querySelector('.cmyd-reset-btn');
        if (resetBtn) {
          resetBtn.setAttribute('disabled', 'true');
          resetBtn.onclick = null;
        }
      }
      
      if (canvas) canvas.style.display = 'none';
      if (placeholder) placeholder.style.display = 'block';
      
      const frameBody = frameEl.querySelector('.frame-body');
      if (frameBody) frameBody.onclick = null;
    }
  }
}

// Render processed thumbnail inside a frame canvas using Cut/Overall constraints
async function renderFrameThumbnail(item, canvas) {
  try {
    if (!item.file && item.handle) {
      item.file = await item.handle.getFile();
    }
    const file = item.file;
    const urlSrc = item.url;
    if (!file && !urlSrc) return;
    
    if (!item.originalImageObject) {
      await new Promise((resolve, reject) => {
        const url = file ? URL.createObjectURL(file) : urlSrc;
        const img = new Image();
        img.onload = () => {
          item.originalImageObject = img;
          if (item.printMode === 'cut') {
            const targetRatio = getChannelRatio(img.naturalWidth, img.naturalHeight, activeChannel);
            item.crop = getDefaultCropForRatio(img.naturalWidth, img.naturalHeight, targetRatio);
            item.isCropped = true;
          }
          if (file) URL.revokeObjectURL(url);
          resolve();
        };
        img.onerror = () => reject(new Error(`Failed to load image: ${item.name}`));
        img.src = url;
      });
    }
    
    const img = item.originalImageObject;
    const w = img.naturalWidth;
    const h = img.naturalHeight;
    const targetRatio = getChannelRatio(w, h, activeChannel);
    
    // Dynamic boundary constraints based on aspect ratio
    const maxBound = 320; // Increased frame limits
    let targetW = maxBound;
    let targetH = Math.round(maxBound / targetRatio);
    if (targetRatio < 1.0) {
      targetH = maxBound;
      targetW = Math.round(maxBound * targetRatio);
    }
    
    canvas.width = targetW;
    canvas.height = targetH;
    
    const tempCanvas = document.createElement('canvas');
    tempCanvas.width = targetW;
    tempCanvas.height = targetH;
    const tempCtx = tempCanvas.getContext('2d');
    
    // Apply crop on the original image
    const crop = item.crop || { x: 0, y: 0, w: 1, h: 1 };
    const cropX = Math.round(crop.x * w);
    const cropY = Math.round(crop.y * h);
    const cropW = Math.max(1, Math.round(crop.w * w));
    const cropH = Math.max(1, Math.round(crop.h * h));
    
    if (item.printMode === 'cut') {
      tempCtx.drawImage(img, cropX, cropY, cropW, cropH, 0, 0, targetW, targetH);
    } else {
      tempCtx.fillStyle = '#ffffff';
      tempCtx.fillRect(0, 0, targetW, targetH);
      
      const imgRatio = cropW / cropH;
      let drawW = targetW;
      let drawH = targetH;
      let drawX = 0;
      let drawY = 0;
      
      if (imgRatio > targetRatio) {
        drawH = targetW / imgRatio;
        drawY = (targetH - drawH) / 2;
      } else {
        drawW = targetH * imgRatio;
        drawX = (targetW - drawW) / 2;
      }
      tempCtx.drawImage(img, cropX, cropY, cropW, cropH, drawX, drawY, drawW, drawH);
    }
    
    const ctx = canvas.getContext('2d');
    ctx.drawImage(tempCanvas, 0, 0);
    
    // Apply edits
    const ep = item.editParams;
    if (ep.chkColorCorrection) {
      applyColorCorrectionToCtx(tempCtx, ctx, targetW, targetH, ep);
    } else {
      applyManualAdjustmentsToCtx(tempCtx, ctx, targetW, targetH, ep);
    }
    
    if (templateImage) {
      applyTemplateOverlayToCtx(ctx, targetW, targetH);
    }
  } catch (err) {
    console.error("Frame thumbnail render error", err);
  }
}

// ----------------------------------------------------
// View Toggles: Grid View vs. Detail Zoom View
// ----------------------------------------------------
function switchToGridView() {
  viewMode = 'grid';
  els.detailModeContainer.style.display = 'none';
  els.gridModeContainer.style.display = 'flex';
  if (els.btnToggleViewMode) els.btnToggleViewMode.innerHTML = `<i class="fa-solid fa-magnifying-glass-plus"></i> Detail Zoom`;
  
  // Stop crop overlays and reset 1:1 zoom
  cropActive = false;
  is1to1Zoom = false;
  if (els.previewViewport) els.previewViewport.classList.remove('zoom-1to1');
  if (els.btnZoom1to1) {
    els.btnZoom1to1.innerHTML = `<i class="fa-solid fa-magnifying-glass-plus"></i> 1:1 Zoom`;
    els.btnZoom1to1.classList.remove('btn-accent');
  }
  if (els.cropOverlay) els.cropOverlay.style.display = 'none';
  if (els.singleFrameContextMenu) els.singleFrameContextMenu.style.display = 'none';
  
  updateGrid();
}

function switchToDetailView(startInCropMode = false) {
  if (!activeItem) {
    showToast('Select an image to preview.', 'error');
    return;
  }
  
  viewMode = 'detail';
  els.gridModeContainer.style.display = 'none';
  els.detailModeContainer.style.display = 'flex';
  if (els.btnToggleViewMode) els.btnToggleViewMode.innerHTML = `<i class="fa-solid fa-grid-horizontal"></i> Monitor Session`;
  
  els.detailFilenameDisplay.textContent = activeItem.name;
  
  // Reset 1:1 zoom on entry
  is1to1Zoom = false;
  if (els.previewViewport) els.previewViewport.classList.remove('zoom-1to1');
  if (els.btnZoom1to1) {
    els.btnZoom1to1.innerHTML = `<i class="fa-solid fa-magnifying-glass-plus"></i> 1:1 Zoom`;
    els.btnZoom1to1.classList.remove('btn-accent');
  }
  if (els.singleFrameContextMenu) els.singleFrameContextMenu.style.display = 'none';

  // Sync detail sizing buttons
  if (activeItem.printMode === 'cut') {
    els.btnDetailModeCut.classList.add('active');
    els.btnDetailModeOverall.classList.remove('active');
  } else {
    els.btnDetailModeCut.classList.remove('active');
    els.btnDetailModeOverall.classList.add('active');
  }
  
  cropActive = startInCropMode;
  els.cropOverlay.style.display = cropActive ? 'block' : 'none';
  els.btnToggleCropTool.className = `btn btn-sm ${cropActive ? 'btn-accent' : 'btn-primary'}`;
  
  loadDetailImage();
}

// ----------------------------------------------------
// Detail View Canvas & Split Rendering
// ----------------------------------------------------
async function loadDetailImage() {
  const item = activeItem;
  if (!item) return;
  
  const ctx = els.previewCanvas.getContext('2d');
  els.previewCanvas.width = 400;
  els.previewCanvas.height = 300;
  ctx.fillStyle = '#07090e';
  ctx.fillRect(0, 0, 400, 300);
  ctx.fillStyle = '#64748b';
  ctx.font = "14px 'Inter', sans-serif";
  ctx.textAlign = 'center';
  ctx.fillText(`Loading detail image...`, 200, 150);
  
  try {
    if (!item.file && item.handle) {
      item.file = await item.handle.getFile();
    }
    const file = item.file;
    const urlSrc = item.url;
    if (!file && !urlSrc) throw new Error("File not loaded.");
    
    const url = file ? URL.createObjectURL(file) : urlSrc;
    originalPreviewImg = new Image();
    originalPreviewImg.onload = function() {
      if (file) URL.revokeObjectURL(url);
      
      const maxDim = is1to1Zoom ? Math.max(originalPreviewImg.naturalWidth, originalPreviewImg.naturalHeight) : 1200;
      let w = originalPreviewImg.naturalWidth;
      let h = originalPreviewImg.naturalHeight;
      
      if (!is1to1Zoom && (w > maxDim || h > maxDim)) {
        if (w > h) {
          h = Math.round((h * maxDim) / w);
          w = maxDim;
        } else {
          w = Math.round((w * maxDim) / h);
          h = maxDim;
        }
      }
      
      originalPreviewCanvas = document.createElement('canvas');
      processedPreviewCanvas = document.createElement('canvas');
      
      recomputeProcessedPreview();
    };
    originalPreviewImg.src = url;
  } catch (err) {
    addLog(`Error loading detail preview: ${err.message}`, 'error');
  }
}

function recomputeProcessedPreview() {
  if (!originalPreviewImg || !originalPreviewCanvas || !processedPreviewCanvas || !activeItem) return;
  
  const img = originalPreviewImg;
  const w = img.naturalWidth;
  const h = img.naturalHeight;
  
  const maxDim = is1to1Zoom ? Math.max(w, h) : 1200;
  let previewW = w;
  let previewH = h;
  if (!is1to1Zoom && (w > maxDim || h > maxDim)) {
    if (w > h) {
      previewH = Math.round((h * maxDim) / w);
      previewW = maxDim;
    } else {
      previewW = Math.round((w * maxDim) / h);
      previewH = maxDim;
    }
  }
  
  const targetRatio = getChannelRatio(w, h, activeChannel);
  const crop = activeItem.crop || { x: 0, y: 0, w: 1, h: 1 };
  
  let drawW = previewW;
  let drawH = previewH;
  
  if (cropActive) {
    // Crop overlay editing shows full image bounds
    originalPreviewCanvas.width = previewW;
    originalPreviewCanvas.height = previewH;
    originalPreviewCanvas.getContext('2d').drawImage(img, 0, 0, previewW, previewH);
    
    processedPreviewCanvas.width = previewW;
    processedPreviewCanvas.height = previewH;
    
    const srcCtx = originalPreviewCanvas.getContext('2d');
    const destCtx = processedPreviewCanvas.getContext('2d');
    destCtx.drawImage(originalPreviewCanvas, 0, 0);
    
    const ep = activeItem.editParams;
    if (ep.chkColorCorrection) {
      applyColorCorrectionToCtx(srcCtx, destCtx, previewW, previewH, ep);
    } else {
      applyManualAdjustmentsToCtx(srcCtx, destCtx, previewW, previewH, ep);
    }
    
    if (templateImage) {
      applyTemplateOverlayToCtx(destCtx, previewW, previewH);
    }
    
    els.previewCanvas.width = previewW;
    els.previewCanvas.height = previewH;
  } else {
    // Normal Preview View
    const cropX = Math.round(crop.x * previewW);
    const cropY = Math.round(crop.y * previewH);
    const cropW = Math.max(1, Math.round(crop.w * previewW));
    const cropH = Math.max(1, Math.round(crop.h * previewH));
    
    if (activeItem.printMode === 'cut') {
      // Cut mode - sizing canvas fits crop box
      drawW = cropW;
      drawH = cropH;
      
      originalPreviewCanvas.width = drawW;
      originalPreviewCanvas.height = drawH;
      
      const fullCanvas = document.createElement('canvas');
      fullCanvas.width = previewW;
      fullCanvas.height = previewH;
      fullCanvas.getContext('2d').drawImage(img, 0, 0, previewW, previewH);
      originalPreviewCanvas.getContext('2d').drawImage(fullCanvas, cropX, cropY, cropW, cropH, 0, 0, drawW, drawH);
      
      processedPreviewCanvas.width = drawW;
      processedPreviewCanvas.height = drawH;
      processedPreviewCanvas.getContext('2d').drawImage(originalPreviewCanvas, 0, 0);
      
      const srcCtx = originalPreviewCanvas.getContext('2d');
      const destCtx = processedPreviewCanvas.getContext('2d');
      const ep = activeItem.editParams;
      if (ep.chkColorCorrection) {
        applyColorCorrectionToCtx(srcCtx, destCtx, drawW, drawH, ep);
      } else {
        applyManualAdjustmentsToCtx(srcCtx, destCtx, drawW, drawH, ep);
      }
      
      if (templateImage) {
        applyTemplateOverlayToCtx(destCtx, drawW, drawH);
      }
      
      els.previewCanvas.width = drawW;
      els.previewCanvas.height = drawH;
    } else {
      // Overall Mode - Canvas size matches channel ratio, letterboxing inside
      drawW = previewW;
      drawH = Math.round(previewW / targetRatio);
      if (targetRatio < 1.0) {
        drawH = previewH;
        drawW = Math.round(previewH * targetRatio);
      }
      
      originalPreviewCanvas.width = drawW;
      originalPreviewCanvas.height = drawH;
      
      const origCtx = originalPreviewCanvas.getContext('2d');
      origCtx.fillStyle = '#ffffff';
      origCtx.fillRect(0, 0, drawW, drawH);
      
      const imgRatio = cropW / cropH;
      let fitW = drawW;
      let fitH = drawH;
      let fitX = 0;
      let fitY = 0;
      
      if (imgRatio > targetRatio) {
        fitH = drawW / imgRatio;
        fitY = (drawH - fitH) / 2;
      } else {
        fitW = drawH * imgRatio;
        fitX = (drawW - fitW) / 2;
      }
      
      const fullCanvas = document.createElement('canvas');
      fullCanvas.width = previewW;
      fullCanvas.height = previewH;
      fullCanvas.getContext('2d').drawImage(img, 0, 0, previewW, previewH);
      
      origCtx.drawImage(fullCanvas, cropX, cropY, cropW, cropH, fitX, fitY, fitW, fitH);
      
      processedPreviewCanvas.width = drawW;
      processedPreviewCanvas.height = drawH;
      
      const destCtx = processedPreviewCanvas.getContext('2d');
      destCtx.drawImage(originalPreviewCanvas, 0, 0);
      
      const ep = activeItem.editParams;
      if (ep.chkColorCorrection) {
        applyColorCorrectionToCtx(origCtx, destCtx, drawW, drawH, ep);
      } else {
        applyManualAdjustmentsToCtx(origCtx, destCtx, drawW, drawH, ep);
      }
      
      if (templateImage) {
        applyTemplateOverlayToCtx(destCtx, drawW, drawH);
      }
      
      els.previewCanvas.width = drawW;
      els.previewCanvas.height = drawH;
    }
  }
  
  setTimeout(() => {
    resizePreviewCanvasContainer();
  }, 10);
}

function resizePreviewCanvasContainer() {
  if (!activeItem || viewMode !== 'detail') return;
  
  if (is1to1Zoom) {
    els.canvasWrapper.style.width = `${els.previewCanvas.width}px`;
    els.canvasWrapper.style.height = `${els.previewCanvas.height}px`;
    els.previewCanvas.style.width = `${els.previewCanvas.width}px`;
    els.previewCanvas.style.height = `${els.previewCanvas.height}px`;
  } else {
    els.previewCanvas.style.width = '';
    els.previewCanvas.style.height = '';
    const rect = els.previewCanvas.getBoundingClientRect();
    els.canvasWrapper.style.width = `${rect.width}px`;
    els.canvasWrapper.style.height = `${rect.height}px`;
  }
  
  updateSliderPositionDOM();
  drawComparison();
  updateCropBoxDOM();
}

function drawComparison() {
  if (!originalPreviewCanvas || !processedPreviewCanvas) return;
  
  const w = els.previewCanvas.width;
  const h = els.previewCanvas.height;
  const ctx = els.previewCanvas.getContext('2d');
  
  ctx.clearRect(0, 0, w, h);
  
  if (cropActive) {
    ctx.drawImage(processedPreviewCanvas, 0, 0);
    return;
  }
  
  const splitX = Math.round(w * splitPercent);
  
  ctx.save();
  ctx.beginPath();
  ctx.rect(0, 0, splitX, h);
  ctx.clip();
  ctx.drawImage(originalPreviewCanvas, 0, 0);
  ctx.restore();
  
  ctx.save();
  ctx.beginPath();
  ctx.rect(splitX, 0, w - splitX, h);
  ctx.clip();
  ctx.drawImage(processedPreviewCanvas, 0, 0);
  ctx.restore();
  
  ctx.strokeStyle = '#06b6d4';
  ctx.lineWidth = 3;
  ctx.shadowColor = 'rgba(6, 182, 212, 0.6)';
  ctx.shadowBlur = 10;
  ctx.beginPath();
  ctx.moveTo(splitX, 0);
  ctx.lineTo(splitX, h);
  ctx.stroke();
  ctx.shadowBlur = 0;
}

function updateSliderPositionDOM() {
  if (!activeItem || cropActive || viewMode !== 'detail' || !els.comparisonSliderBar) {
    if (els.comparisonSliderBar) els.comparisonSliderBar.style.display = 'none';
    return;
  }
  
  els.comparisonSliderBar.style.display = 'block';
  
  const canvasWidth = els.previewCanvas.offsetWidth;
  const canvasHeight = els.previewCanvas.offsetHeight;
  const canvasLeft = els.previewCanvas.offsetLeft;
  
  const leftPx = canvasLeft + (canvasWidth * splitPercent);
  els.comparisonSliderBar.style.left = `${leftPx}px`;
  els.comparisonSliderBar.style.height = `${canvasHeight}px`;
  els.comparisonSliderBar.style.top = `${els.previewCanvas.offsetTop}px`;
}

function triggerPreviewRecomputation() {
  if (viewMode === 'detail') {
    recomputeProcessedPreview();
  } else {
    updateGrid();
  }
}

// ----------------------------------------------------
// Interactive Crop Engine (With Aspect Ratio Lock)
// ----------------------------------------------------
function toggleCropMode() {
  if (viewMode !== 'detail' || !activeItem) return;
  
  cropActive = !cropActive;
  els.cropOverlay.style.display = cropActive ? 'block' : 'none';
  els.btnToggleCropTool.className = `btn btn-sm ${cropActive ? 'btn-accent' : 'btn-primary'}`;
  
  recomputeProcessedPreview();
}

function resetCropCoordinates() {
  if (!activeItem) return;
  
  activeItem.manualCropEdited = false;
  if (activeItem.printMode === 'cut' && originalPreviewImg) {
    const targetRatio = getChannelRatio(originalPreviewImg.naturalWidth, originalPreviewImg.naturalHeight, activeChannel);
    activeItem.crop = getDefaultCropForRatio(originalPreviewImg.naturalWidth, originalPreviewImg.naturalHeight, targetRatio);
    activeItem.isCropped = true;
  } else {
    activeItem.crop = { x: 0, y: 0, w: 1, h: 1 };
    activeItem.isCropped = false;
  }
  
  addLog(`Reset crop coordinates for: ${activeItem.name}`, 'info');
  showToast('Crop reset', 'info');
  
  if (cropActive) {
    updateCropBoxDOM();
  } else {
    recomputeProcessedPreview();
  }
}

function updateCropBoxDOM() {
  if (!activeItem || !cropActive || !els.cropBox) return;
  const crop = activeItem.crop;
  
  els.cropBox.style.left = `${crop.x * 100}%`;
  els.cropBox.style.top = `${crop.y * 100}%`;
  els.cropBox.style.width = `${crop.w * 100}%`;
  els.cropBox.style.height = `${crop.h * 100}%`;
}

// Mouse event handlers for crop box sizing with aspect ratio lock constraints
function handleCropMouseDown(e) {
  if (!activeItem || !cropActive) return;
  e.stopPropagation();
  e.preventDefault();
  
  isDraggingCrop = true;
  cropDragType = e.target.dataset.handle || 'move';
  
  cropStartMouse = { x: e.clientX, y: e.clientY };
  cropStartBox = { ...activeItem.crop };
}

function handleCropMouseMove(e) {
  if (!isDraggingCrop || !activeItem || !cropActive || !originalPreviewImg) return;
  e.preventDefault();
  
  const rect = els.previewCanvas.getBoundingClientRect();
  const deltaX = (e.clientX - cropStartMouse.x) / rect.width;
  const deltaY = (e.clientY - cropStartMouse.y) / rect.height;
  
  const crop = { ...cropStartBox };
  const minSize = 0.1; // minimum crop size 10%
  
  if (cropDragType === 'move') {
    crop.x = Math.max(0, Math.min(1 - crop.w, cropStartBox.x + deltaX));
    crop.y = Math.max(0, Math.min(1 - crop.h, cropStartBox.y + deltaY));
  } else {
    // If aspect ratio is locked (Cut mode):
    if (activeItem.printMode === 'cut') {
      const img = originalPreviewImg;
      const targetRatio = getChannelRatio(img.naturalWidth, img.naturalHeight, activeChannel);
      const k = (rect.width / rect.height) / targetRatio; // scale adjustment factor
      
      // crop.h must equal crop.w * k
      if (cropDragType.includes('e') || cropDragType.includes('w')) {
        if (cropDragType.includes('w')) {
          const newX = Math.max(0, Math.min(cropStartBox.x + cropStartBox.w - minSize, cropStartBox.x + deltaX));
          crop.w = cropStartBox.x + cropStartBox.w - newX;
          crop.x = newX;
        } else {
          crop.w = Math.max(minSize, Math.min(1 - cropStartBox.x, cropStartBox.w + deltaX));
        }
        
        crop.h = crop.w * k;
        // Check Y boundary constraints
        if (crop.y + crop.h > 1.0) {
          crop.h = 1.0 - crop.y;
          crop.w = crop.h / k;
          if (cropDragType.includes('w')) {
            crop.x = cropStartBox.x + cropStartBox.w - crop.w;
          }
        }
      } else if (cropDragType.includes('n') || cropDragType.includes('s')) {
        if (cropDragType.includes('n')) {
          const newY = Math.max(0, Math.min(cropStartBox.y + cropStartBox.h - minSize, cropStartBox.y + deltaY));
          crop.h = cropStartBox.y + cropStartBox.h - newY;
          crop.y = newY;
        } else {
          crop.h = Math.max(minSize, Math.min(1 - cropStartBox.y, cropStartBox.h + deltaY));
        }
        
        crop.w = crop.h / k;
        // Check X boundary constraints
        if (crop.x + crop.w > 1.0) {
          crop.w = 1.0 - crop.x;
          crop.h = crop.w * k;
          if (cropDragType.includes('n')) {
            crop.y = cropStartBox.y + cropStartBox.h - crop.h;
          }
        }
      }
    } else {
      // Freeform dragging in Overall mode
      if (cropDragType.includes('w')) {
        const newX = Math.max(0, Math.min(cropStartBox.x + cropStartBox.w - minSize, cropStartBox.x + deltaX));
        crop.w = cropStartBox.x + cropStartBox.w - newX;
        crop.x = newX;
      }
      if (cropDragType.includes('e')) {
        crop.w = Math.max(minSize, Math.min(1 - cropStartBox.x, cropStartBox.w + deltaX));
      }
      if (cropDragType.includes('n')) {
        const newY = Math.max(0, Math.min(cropStartBox.y + cropStartBox.h - minSize, cropStartBox.y + deltaY));
        crop.h = cropStartBox.y + cropStartBox.h - newY;
        crop.y = newY;
      }
      if (cropDragType.includes('s')) {
        crop.h = Math.max(minSize, Math.min(1 - cropStartBox.y, cropStartBox.h + deltaY));
      }
    }
  }
  
  activeItem.crop = crop;
  activeItem.manualCropEdited = true;
  activeItem.isCropped = true;
  
  updateCropBoxDOM();
}

function handleCropMouseUp() {
  if (isDraggingCrop) {
    isDraggingCrop = false;
  }
}

// ----------------------------------------------------
// Image Processing calculations (Updated for Noritsu CMYD)
// ----------------------------------------------------
function applyColorCorrectionToCtx(srcCtx, destCtx, w, h, ep) {
  const imgData = srcCtx.getImageData(0, 0, w, h);
  const data = imgData.data;
  const len = data.length;
  const mode = ep.correctionAlgorithm;
  
  let minR = 0, maxR = 255;
  let minG = 0, maxG = 255;
  let minB = 0, maxB = 255;
  
  if (mode === 'contrast' || mode === 'both') {
    const histR = new Int32Array(256);
    const histG = new Int32Array(256);
    const histB = new Int32Array(256);
    
    for (let i = 0; i < len; i += 4) {
      histR[data[i]]++;
      histG[data[i+1]]++;
      histB[data[i+2]]++;
    }
    
    const numPixels = len / 4;
    const clipCount = numPixels * 0.01; 
    
    let sum = 0;
    for (let i = 0; i < 256; i++) {
      sum += histR[i];
      if (sum >= clipCount) { minR = i; break; }
    }
    sum = 0;
    for (let i = 255; i >= 0; i--) {
      sum += histR[i];
      if (sum >= clipCount) { maxR = i; break; }
    }
    
    sum = 0;
    for (let i = 0; i < 256; i++) {
      sum += histG[i];
      if (sum >= clipCount) { minG = i; break; }
    }
    sum = 0;
    for (let i = 255; i >= 0; i--) {
      sum += histG[i];
      if (sum >= clipCount) { maxG = i; break; }
    }
    
    sum = 0;
    for (let i = 0; i < 256; i++) {
      sum += histB[i];
      if (sum >= clipCount) { minB = i; break; }
    }
    sum = 0;
    for (let i = 255; i >= 0; i--) {
      sum += histB[i];
      if (sum >= clipCount) { maxB = i; break; }
    }
  }

  let scaleR = 1.0, scaleG = 1.0, scaleB = 1.0;
  if (mode === 'awb' || mode === 'both') {
    let sumR = 0, sumG = 0, sumB = 0;
    for (let i = 0; i < len; i += 4) {
      sumR += data[i];
      sumG += data[i+1];
      sumB += data[i+2];
    }
    const numPixels = len / 4;
    const avgR = sumR / numPixels;
    const avgG = sumG / numPixels;
    const avgB = sumB / numPixels;
    const gray = (avgR + avgG + avgB) / 3;
    
    if (avgR > 0) scaleR = gray / avgR;
    if (avgG > 0) scaleG = gray / avgG;
    if (avgB > 0) scaleB = gray / avgB;
  }

  // Retrieve CMYD color offsets scaled by configured sensitivity percentage
  const colorScale = (colorStepPct / 100) * 100; // e.g. 2.5% = 2.5 units per step; 5% = 5.0 units per step
  const densityScale = (densityStepPct / 100) * 100;
  const cVal = parseFloat(ep.paramC) * colorScale; 
  const mVal = parseFloat(ep.paramM) * colorScale;
  const yVal = parseFloat(ep.paramY) * colorScale;
  const dVal = parseFloat(ep.paramD) * densityScale;
  
  const cContrast = parseInt(ep.paramContrast) * 2.5;
  const cFactor = (259 * (cContrast + 255)) / (255 * (259 - cContrast));
  const sFactor = (parseInt(ep.paramSaturation) + 50) / 50; 

  const targetData = destCtx.getImageData(0, 0, w, h);
  const tData = targetData.data;

  const stretchR = 255 / (maxR - minR || 1);
  const stretchG = 255 / (maxG - minG || 1);
  const stretchB = 255 / (maxB - minB || 1);

  for (let i = 0; i < len; i += 4) {
    let r = data[i];
    let g = data[i+1];
    let b = data[i+2];
    
    if (mode === 'contrast' || mode === 'both') {
      r = (r - minR) * stretchR;
      g = (g - minG) * stretchG;
      b = (b - minB) * stretchB;
    }
    
    if (mode === 'awb' || mode === 'both') {
      r *= scaleR;
      g *= scaleG;
      b *= scaleB;
    }
    
    // Apply Noritsu CMYD offsets
    // Cyan increases subtract Red. Density (D) increases add brightness to all channels.
    r = r - cVal + dVal;
    g = g - mVal + dVal;
    b = b - yVal + dVal;
    
    if (cContrast !== 0) {
      r = cFactor * (r - 128) + 128;
      g = cFactor * (g - 128) + 128;
      b = cFactor * (b - 128) + 128;
    }
    
    if (sFactor !== 1.0) {
      const lum = 0.299 * r + 0.587 * g + 0.114 * b;
      r = lum + (r - lum) * sFactor;
      g = lum + (g - lum) * sFactor;
      b = lum + (b - lum) * sFactor;
    }
    
    tData[i]   = Math.max(0, Math.min(255, r));
    tData[i+1] = Math.max(0, Math.min(255, g));
    tData[i+2] = Math.max(0, Math.min(255, b));
    tData[i+3] = data[i+3];
  }
  
  destCtx.putImageData(targetData, 0, 0);
}

function applyManualAdjustmentsToCtx(srcCtx, destCtx, w, h, ep) {
  const colorScale = (colorStepPct / 100) * 100;
  const densityScale = (densityStepPct / 100) * 100;
  const cVal = parseFloat(ep.paramC) * colorScale; 
  const mVal = parseFloat(ep.paramM) * colorScale;
  const yVal = parseFloat(ep.paramY) * colorScale;
  const dVal = parseFloat(ep.paramD) * densityScale;
  
  const cContrast = parseInt(ep.paramContrast) * 2.5;
  const sVal = parseInt(ep.paramSaturation);
  const sharpVal = parseInt(ep.paramSPD) || 0;
  
  if (cVal === 0 && mVal === 0 && yVal === 0 && dVal === 0 && cContrast === 0 && sVal === 0 && sharpVal === 0) return;
  
  const imgData = srcCtx.getImageData(0, 0, w, h);
  const data = imgData.data;
  const len = data.length;
  
  const targetData = destCtx.getImageData(0, 0, w, h);
  const tData = targetData.data;
  
  const cFactor = (259 * (cContrast + 255)) / (255 * (259 - cContrast));
  const sFactor = (sVal + 50) / 50;

  for (let i = 0; i < len; i += 4) {
    let r = data[i];
    let g = data[i+1];
    let b = data[i+2];
    
    r = r - cVal + dVal;
    g = g - mVal + dVal;
    b = b - yVal + dVal;
    
    if (cContrast !== 0) {
      r = cFactor * (r - 128) + 128;
      g = cFactor * (g - 128) + 128;
      b = cFactor * (b - 128) + 128;
    }
    
    if (sFactor !== 1.0) {
      const lum = 0.299 * r + 0.587 * g + 0.114 * b;
      r = lum + (r - lum) * sFactor;
      g = lum + (g - lum) * sFactor;
      b = lum + (b - lum) * sFactor;
    }
    
    tData[i]   = Math.max(0, Math.min(255, r));
    tData[i+1] = Math.max(0, Math.min(255, g));
    tData[i+2] = Math.max(0, Math.min(255, b));
    tData[i+3] = data[i+3];
  }
  destCtx.putImageData(targetData, 0, 0);

  // Apply sharpness / softness via unsharp mask if paramSPD != 0
  if (sharpVal !== 0) {
    const sharpAmount = sharpVal / 20; // range: -1.0 to +1.0
    const blurred = destCtx.getImageData(0, 0, w, h);
    const blurData = blurred.data;
    // Box-blur pass (3x3) into a temp array to serve as the "blur" image
    const blurBuf = new Uint8ClampedArray(len);
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        let rSum = 0, gSum = 0, bSum = 0, count = 0;
        for (let dy = -1; dy <= 1; dy++) {
          for (let dx = -1; dx <= 1; dx++) {
            const nx = Math.min(w - 1, Math.max(0, x + dx));
            const ny = Math.min(h - 1, Math.max(0, y + dy));
            const ni = (ny * w + nx) * 4;
            rSum += blurData[ni];
            gSum += blurData[ni + 1];
            bSum += blurData[ni + 2];
            count++;
          }
        }
        const idx = (y * w + x) * 4;
        blurBuf[idx]     = rSum / count;
        blurBuf[idx + 1] = gSum / count;
        blurBuf[idx + 2] = bSum / count;
        blurBuf[idx + 3] = blurData[idx + 3];
      }
    }
    // Unsharp mask: result = original + amount * (original - blur)
    const sharp = destCtx.getImageData(0, 0, w, h);
    const sharpData = sharp.data;
    for (let i = 0; i < len; i += 4) {
      sharpData[i]     = Math.max(0, Math.min(255, blurData[i]     + sharpAmount * (blurData[i]     - blurBuf[i])));
      sharpData[i + 1] = Math.max(0, Math.min(255, blurData[i + 1] + sharpAmount * (blurData[i + 1] - blurBuf[i + 1])));
      sharpData[i + 2] = Math.max(0, Math.min(255, blurData[i + 2] + sharpAmount * (blurData[i + 2] - blurBuf[i + 2])));
      sharpData[i + 3] = blurData[i + 3];
    }
    destCtx.putImageData(sharp, 0, 0);
  }
}

function applyTemplateOverlayToCtx(ctx, imgW, imgH) {
  const opacity = parseFloat(els.templateOpacity.value) / 100;
  const userScale = parseFloat(els.templateScale.value) / 100;
  const pos = els.templatePosition.value;
  const margin = parseInt(els.templateMargin.value);
  
  const tW = templateImage.naturalWidth;
  const tH = templateImage.naturalHeight;
  
  let drawW = 0, drawH = 0;
  let drawX = 0, drawY = 0;
  
  if (pos === 'stretch') {
    drawW = imgW;
    drawH = imgH;
    drawX = 0;
    drawY = 0;
  } else if (pos === 'center') {
    const aspectFitScale = Math.min(imgW / tW, imgH / tH);
    const finalScale = aspectFitScale * userScale;
    
    drawW = tW * finalScale;
    drawH = tH * finalScale;
    drawX = (imgW - drawW) / 2;
    drawY = (imgH - drawH) / 2;
  } else {
    const scaleFactor = (imgW / 1920) * userScale;
    drawW = tW * scaleFactor;
    drawH = tH * scaleFactor;
    
    if (drawW > imgW || drawH > imgH) {
      const resizeScale = Math.min(imgW / drawW, imgH / drawH) * 0.9;
      drawW *= resizeScale;
      drawH *= resizeScale;
    }
    
    const actualMargin = margin * (imgW / 1920);
    
    switch (pos) {
      case 'top-left':
        drawX = actualMargin;
        drawY = actualMargin;
        break;
      case 'top-right':
        drawX = imgW - drawW - actualMargin;
        drawY = actualMargin;
        break;
      case 'bottom-left':
        drawX = actualMargin;
        drawY = imgH - drawH - actualMargin;
        break;
      case 'bottom-right':
      default:
        drawX = imgW - drawW - actualMargin;
        drawY = imgH - drawH - actualMargin;
        break;
    }
  }
  
  ctx.save();
  ctx.globalAlpha = opacity;
  ctx.drawImage(templateImage, drawX, drawY, drawW, drawH);
  ctx.restore();
}

// ----------------------------------------------------
// Print Engine (Connects directly to PowerShell Local Server)
// ----------------------------------------------------
async function printImage(item) {

  addLog(`[Printer] Preparing print layout for ${item.name}...`, 'info');
  item.status = 'processing';
  updateGrid();
  
  try {
    if (!item.file && item.handle) {
      item.file = await item.handle.getFile();
    }
    const file = item.file;
    const urlSrc = item.url;
    if (!file && !urlSrc) throw new Error("Image source not loaded.");
    
    if (!item.originalImageObject) {
      await new Promise((resolve, reject) => {
        const url = file ? URL.createObjectURL(file) : urlSrc;
        const img = new Image();
        img.onload = () => {
          item.originalImageObject = img;
          if (file) URL.revokeObjectURL(url);
          resolve();
        };
        img.onerror = () => reject(new Error(`Failed to load image: ${item.name}`));
        img.src = url;
      });
    }
    
    const img = item.originalImageObject;
    const fullW = img.naturalWidth;
    const fullH = img.naturalHeight;
    const targetRatio = getChannelRatio(fullW, fullH, activeChannel);
    
    const crop = item.crop || { x: 0, y: 0, w: 1, h: 1 };
    const cropX = Math.round(crop.x * fullW);
    const cropY = Math.round(crop.y * fullH);
    const cropW = Math.max(1, Math.round(crop.w * fullW));
    const cropH = Math.max(1, Math.round(crop.h * fullH));
    
    let canvasW = cropW;
    let canvasH = cropH;
    
    const procCanvas = document.createElement('canvas');
    
    if (item.printMode === 'cut') {
      procCanvas.width = canvasW;
      procCanvas.height = canvasH;
      const procCtx = procCanvas.getContext('2d');
      procCtx.drawImage(img, cropX, cropY, cropW, cropH, 0, 0, canvasW, canvasH);
      
      const ep = item.editParams;
      const tempCanvas = document.createElement('canvas');
      tempCanvas.width = canvasW;
      tempCanvas.height = canvasH;
      const tempCtx = tempCanvas.getContext('2d');
      tempCtx.drawImage(procCanvas, 0, 0);
      
      // Print output: apply CMYD/contrast/saturation corrections only.
      // Auto-profile algorithms (AWB, contrast-stretch) are NOT applied to the
      // print file — colour rendering is left to the printer's own settings.
      applyManualAdjustmentsToCtx(tempCtx, procCtx, canvasW, canvasH, ep);
      
      if (templateImage) {
        applyTemplateOverlayToCtx(procCtx, canvasW, canvasH);
      }
    } else {
      // Overall Mode - Canvas size matches channel ratio, letterboxing inside
      const imgRatio = cropW / cropH;
      if (imgRatio > targetRatio) {
        canvasW = cropW;
        canvasH = Math.round(cropW / targetRatio);
      } else {
        canvasH = cropH;
        canvasW = Math.round(cropH * targetRatio);
      }
      
      procCanvas.width = canvasW;
      procCanvas.height = canvasH;
      const procCtx = procCanvas.getContext('2d');
      
      procCtx.fillStyle = '#ffffff';
      procCtx.fillRect(0, 0, canvasW, canvasH);
      
      let fitW = canvasW;
      let fitH = canvasH;
      let fitX = 0;
      let fitY = 0;
      
      if (imgRatio > targetRatio) {
        fitH = canvasW / imgRatio;
        fitY = (canvasH - fitH) / 2;
      } else {
        fitW = canvasH * imgRatio;
        fitX = (canvasW - fitW) / 2;
      }
      
      procCtx.drawImage(img, cropX, cropY, cropW, cropH, fitX, fitY, fitW, fitH);
      
      const ep = item.editParams;
      const tempCanvas = document.createElement('canvas');
      tempCanvas.width = canvasW;
      tempCanvas.height = canvasH;
      const tempCtx = tempCanvas.getContext('2d');
      tempCtx.drawImage(procCanvas, 0, 0);
      
      // Print output: apply CMYD/contrast/saturation corrections only.
      // Auto-profile algorithms (AWB, contrast-stretch) are NOT applied to the
      // print file — colour rendering is left to the printer's own settings.
      applyManualAdjustmentsToCtx(tempCtx, procCtx, canvasW, canvasH, ep);
      
      if (templateImage) {
        applyTemplateOverlayToCtx(procCtx, canvasW, canvasH);
      }
    }
    
    // Output high-quality JPEG
    const blob = await new Promise((resolve) => {
      procCanvas.toBlob(resolve, 'image/jpeg', 0.94);
    });
    
    if (!blob) throw new Error("Image rendering failed.");
    
    // Direct print: send to print API without writing to hotfolder
    const qty = item.qty || 1;
    
    // Base64 encode for API execution
    const reader = new FileReader();
    reader.onloadend = async () => {
      const base64Data = reader.result;
      
      try {
        const ch = paperChannels[activeChannel] || paperChannels['6x4'];
        const chLong = Math.max(ch.w, ch.h);
        const chShort = Math.min(ch.w, ch.h);
        
        const response = await fetch('/api/print', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            filename: item.name,
            qty: qty,
            image: base64Data,
            hotFolder: hotFolderPath,
            outputFolder: outputFolderPath,
            printDestination: currentPrintDestination,
            sourcePath: item.path || '',
            // Channel dimensions in mm — server uses these to pick correct paper size and orientation
            channelW: Math.round(chLong * 25.4),  // inches -> mm (long side e.g. 152 mm)
            channelH: Math.round(chShort * 25.4), // inches -> mm (short side e.g. 102 mm)
            channelKey: activeChannel
          })
        });
        
        const data = await response.json();
        if (response.ok && data.status === 'success') {
          addLog(`[Printer] Print Success: ${data.message}`, 'success');
          showToast(`Printed ${item.name} (Qty: ${qty})`, 'success');
          item.status = 'completed';
        } else {
          throw new Error(data.message || "Failed to trigger local print command.");
        }
      } catch (err) {
        addLog(`[Printer] API SDK Call failed: ${err.message}`, 'error');
        showToast('Local print script failed.', 'error');
        item.status = 'failed';
      }
      
      // Copy to archive and clean input if available
      if (item.status === 'completed' && archiveDirHandle && file) {
        try {
          const archiveFileHandle = await archiveDirHandle.getFileHandle(item.name, { create: true });
          const archiveWritable = await archiveFileHandle.createWritable();
          await archiveWritable.write(file);
          await archiveWritable.close();
          addLog(`[Archive] Copied original ${item.name} to archive folder.`, 'info');
        } catch (e) {
          addLog(`[Archive] Failed to archive ${item.name}: ${e.message}`, 'error');
        }
      }
      
      updateGrid();
      renderSourceExplorer();
      renderQueue();
    };
    reader.readAsDataURL(blob);
    
  } catch (err) {
    item.status = 'failed';
    addLog(`[Printer] Error preparing ${item.name}: ${err.message}`, 'error');
    showToast(`Print failed: ${err.message}`, 'error');
    updateGrid();
    renderSourceExplorer();
    renderQueue();
  }
}

async function printActiveGridPage() {
  const selectedFiles = filesQueue.filter(item => item.checked);
  const startIdx = gridPage * 6;
  const pageItems = selectedFiles.slice(startIdx, startIdx + 6).filter(item => !item.passed);
  
  if (pageItems.length === 0) {
    showToast('No eligible photos on this page to print (all unselected or passed)!', 'warning');
    return;
  }
  
  addLog(`[Session] Starting print batch of ${pageItems.length} photos on active page...`, 'warning');
  showToast(`Printing page batch (${pageItems.length} photos)...`, 'info');
  
  for (const item of pageItems) {
    await printImage(item);
  }
}

// ----------------------------------------------------
// Batch Processing Pipeline
// ----------------------------------------------------
async function startBatchProcessing() {
  if (isProcessing) return;
  
  const processableItems = filesQueue.filter(item => item.checked && !item.passed);
  if (processableItems.length === 0) {
    showToast('No photos to process (all selected photos are marked as PASSED)!', 'warning');
    return;
  }
  
  isProcessing = true;
  pauseRequested = false;
  updateUIState();
  
  let firstPendingIndex = filesQueue.findIndex(item => item.checked && !item.passed && (item.status === 'pending' || item.status === 'failed'));
  
  if (firstPendingIndex === -1) {
    filesQueue.forEach(item => {
      if (item.checked && !item.passed) item.status = 'pending';
    });
    firstPendingIndex = filesQueue.findIndex(item => item.checked && !item.passed);
  }
  
  currentIndex = firstPendingIndex;
  batchStartTime = Date.now();
  
  els.processHeaderTitle.innerHTML = `<i class="fa-solid fa-gear fa-spin"></i> Batch Printing Event Photos...`;
  addLog(`Starting batch processing of ${processableItems.length} photos...`, 'warning');
  
  processNextImage();
}

function pauseBatchProcessing() {
  if (!isProcessing) return;
  pauseRequested = true;
  els.btnPauseProcess.innerHTML = `<i class="fa-solid fa-spinner fa-spin"></i> Pausing...`;
  els.btnPauseProcess.classList.add('btn-disabled');
  addLog('Pausing batch queue. Finishing active image...', 'warning');
}

async function processNextImage() {
  while (currentIndex < filesQueue.length && (!filesQueue[currentIndex].checked || filesQueue[currentIndex].passed)) {
    if (filesQueue[currentIndex].passed) {
      addLog(`[PASS] Skipping frame #${currentIndex + 1} (${filesQueue[currentIndex].name}) - marked as PASSED`, 'info');
    }
    currentIndex++;
  }

  if (pauseRequested) {
    isProcessing = false;
    pauseRequested = false;
    els.btnPauseProcess.innerHTML = `<i class="fa-solid fa-pause"></i> Pause Batch`;
    els.processHeaderTitle.textContent = "Batch Processing Paused";
    addLog(`Batch processing paused at image #${currentIndex + 1}.`, 'warning');
    showToast('Batch processing paused.', 'info');
    updateUIState();
    return;
  }
  
  if (currentIndex >= filesQueue.length) {
    isProcessing = false;
    updateUIState();
    els.processHeaderTitle.textContent = "Batch Processing Completed!";
    els.etaContainer.textContent = "ETA: Completed";
    
    const processedCount = filesQueue.filter(item => item.checked && !item.passed).length;
    addLog(`Batch completed. Processed ${processedCount} files.`, 'success');
    showToast('Batch completed successfully!', 'success');
    return;
  }
  
  const currentItem = filesQueue[currentIndex];
  await printImage(currentItem);
  
  currentIndex++;
  updateProgressBar();
  renderSourceExplorer();
  updateSelectionCounts();
  renderQueue();
  updateGrid();
  calculateETA();
  
  setTimeout(processNextImage, 100);
}

function updateProgressBar() {
  const activeItems = filesQueue.filter(item => item.checked && !item.passed);
  const completedCount = activeItems.filter(item => item.status === 'completed').length;
  const failedCount = activeItems.filter(item => item.status === 'failed').length;
  const processed = completedCount + failedCount;
  const total = activeItems.length;
  
  els.processProgressStats.textContent = `${processed} / ${total} selected images processed (${completedCount} success, ${failedCount} failed)`;
  
  if (total > 0) {
    const percent = Math.round((processed / total) * 100);
    els.progressBarFill.style.width = `${percent}%`;
  } else {
    els.progressBarFill.style.width = '0%';
  }
}

function calculateETA() {
  const checkedItems = filesQueue.filter(item => item.checked);
  const completedCount = checkedItems.filter(item => item.status === 'completed').length;
  const failedCount = checkedItems.filter(item => item.status === 'failed').length;
  const processed = completedCount + failedCount;
  
  if (processed <= 0 || !batchStartTime) {
    els.etaContainer.textContent = "ETA: Calculating...";
    return;
  }
  
  const elapsedMs = Date.now() - batchStartTime;
  const avgMsPerImg = elapsedMs / processed;
  
  const remaining = checkedItems.length - processed;
  const remainingMs = avgMsPerImg * remaining;
  
  if (remaining <= 0) {
    els.etaContainer.textContent = "ETA: Completed";
    return;
  }
  
  const totalSeconds = Math.round(remainingMs / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  
  if (minutes > 0) {
    els.etaContainer.textContent = `ETA: ~${minutes}m ${seconds}s`;
  } else {
    els.etaContainer.textContent = `ETA: ~${seconds}s`;
  }
}

// ----------------------------------------------------
// PNG Template Image upload
// ----------------------------------------------------
function handleTemplateUpload(e) {
  const file = e.target.files[0];
  if (!file) return;
  
  if (file.type !== 'image/png') {
    showToast('Template must be a transparent PNG!', 'error');
    els.templateInput.value = '';
    return;
  }
  
  const reader = new FileReader();
  reader.onload = function(event) {
    templateImage = new Image();
    templateImage.onload = function() {
      templateFileName = file.name;
      els.templateName.textContent = file.name;
      els.templateThumbnail.src = event.target.result;
      els.templatePreviewBlock.style.display = 'flex';
      
      addLog(`Template loaded: ${file.name} (${templateImage.width}x${templateImage.height}px)`, 'info');
      showToast('Template PNG loaded successfully.', 'success');
      
      triggerPreviewRecomputation();
    };
    templateImage.src = event.target.result;
  };
  reader.readAsDataURL(file);
}

function removeTemplate() {
  if (isProcessing) return;
  templateImage = null;
  templateFileName = '';
  els.templateInput.value = '';
  els.templatePreviewBlock.style.display = 'none';
  addLog('Template overlay removed.', 'warning');
  showToast('Template removed.', 'info');
  triggerPreviewRecomputation();
}

// ----------------------------------------------------
// Split Slider Drag handles
// ----------------------------------------------------
function startSliderDrag(e) {
  e.preventDefault();
  isDraggingSlider = true;
  els.previewViewport.style.cursor = 'ew-resize';
}

function stopSliderDrag() {
  isDraggingSlider = false;
  els.previewViewport.style.cursor = 'default';
}

function handleSliderDrag(e) {
  if (!isDraggingSlider || !activeItem || cropActive || viewMode !== 'detail') return;
  
  const rect = els.previewCanvas.getBoundingClientRect();
  let percent = (e.clientX - rect.left) / rect.width;
  percent = Math.max(0, Math.min(1, percent));
  
  splitPercent = percent;
  updateSliderPositionDOM();
  drawComparison();
}

// ----------------------------------------------------
// Right Drawer Queue list selection sync (Checked for null)
// ----------------------------------------------------
function toggleAllQueueItems(checkState) {
  if (isProcessing) return;
  filesQueue.forEach(item => {
    item.checked = checkState;
  });
  renderQueue();
  updateProgressBar();
  updateUIState();
  updateGrid();
}

function handleItemCheckboxToggle(item, event) {
  item.checked = event.target.checked;
  updateProgressBar();
  updateUIState();
  updateGrid();
}

function renderQueue() {
  if (!els.queueList) return;
  
  const searchTerm = els.queueSearch ? els.queueSearch.value.toLowerCase() : '';
  const filteredQueue = filesQueue.filter(item => item.name.toLowerCase().includes(searchTerm));
  
  if (els.queueCount) els.queueCount.textContent = `(${filesQueue.length})`;
  
  els.queueList.innerHTML = '';
  filteredQueue.forEach((item) => {
    const safeId = item.name.replace(/\s+/g, '-');
    const itemEl = document.createElement('div');
    itemEl.className = `queue-item ${activeItem && activeItem.name === item.name ? 'active' : ''}`;
    
    let statusClass = 'status-pending';
    let statusLabel = 'Pending';
    if (item.status === 'processing') {
      statusClass = 'status-processing';
      statusLabel = 'Printing';
    } else if (item.status === 'completed') {
      statusClass = 'status-completed';
      statusLabel = 'Printed';
    } else if (item.status === 'failed') {
      statusClass = 'status-failed';
      statusLabel = 'Error';
    }
    
    itemEl.innerHTML = `
      <div class="queue-item-check-container" onclick="event.stopPropagation()">
        <input type="checkbox" class="queue-item-checkbox" id="chk-${safeId}" ${item.checked ? 'checked' : ''}>
      </div>
      <div class="queue-item-thumbnail" id="thumb-${safeId}">
        <i class="fa-regular fa-image"></i>
      </div>
      <div class="queue-item-details">
        <span class="queue-item-name" title="${item.name}">${item.name}</span>
        <span class="queue-item-size" id="size-${safeId}">${item.sizeStr}</span>
      </div>
      <div class="queue-item-qty" onclick="event.stopPropagation()" style="display: flex; align-items: center; gap: 0.25rem; margin-right: 1rem;">
        <label for="qty-${safeId}" style="font-size: 0.75rem; color: var(--text-secondary);">Qty:</label>
        <input type="number" id="qty-${safeId}" class="qty-input" value="${item.qty}" min="1" max="100" style="width: 45px; padding: 0.2rem; background: var(--panel-bg); border: 1px solid var(--border-color); color: var(--text-primary); border-radius: 4px; font-size: 0.8rem;">
      </div>
      <span class="queue-item-status ${statusClass}">${statusLabel}</span>
    `;
    
    const thumbContainer = itemEl.querySelector('.queue-item-thumbnail');
    if (item.originalImageObject) {
      thumbContainer.innerHTML = '';
      const tCanvas = document.createElement('canvas');
      tCanvas.width = 44;
      tCanvas.height = 44;
      const tCtx = tCanvas.getContext('2d');
      const img = item.originalImageObject;
      const crop = item.crop || { x: 0, y: 0, w: 1, h: 1 };
      tCtx.drawImage(
        img,
        Math.round(crop.x * img.naturalWidth), Math.round(crop.y * img.naturalHeight),
        Math.round(crop.w * img.naturalWidth), Math.round(crop.h * img.naturalHeight),
        0, 0, 44, 44
      );
      thumbContainer.appendChild(tCanvas);
    }
    
    const checkInput = itemEl.querySelector('.queue-item-checkbox');
    checkInput.addEventListener('change', (e) => handleItemCheckboxToggle(item, e));

    const qtyInput = itemEl.querySelector('.qty-input');
    qtyInput.addEventListener('change', (e) => {
      let val = parseInt(e.target.value);
      if (isNaN(val) || val < 1) val = 1;
      item.qty = val;
      e.target.value = val;
      updateGrid();
    });
    
    itemEl.addEventListener('click', () => {
      activeItem = item;
      syncSidebarToActiveItem();
      if (viewMode === 'detail') {
        loadDetailImage();
      } else {
        updateGrid();
      }
    });
    
    els.queueList.appendChild(itemEl);
  });
}

// ----------------------------------------------------
// System Logging
// ----------------------------------------------------
function addLog(text, type = 'info') {
  const time = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  const entry = document.createElement('div');
  entry.className = 'log-entry';
  
  let typeClass = 'log-entry-info';
  if (type === 'success') typeClass = 'log-entry-success';
  if (type === 'error') typeClass = 'log-entry-error';
  if (type === 'warning') typeClass = 'log-entry-warning';
  
  entry.innerHTML = `
    <span class="log-time">[${time}]</span>
    <span class="${typeClass}">${text}</span>
  `;
  
  els.logPanel.appendChild(entry);
  els.logPanel.scrollTop = els.logPanel.scrollHeight;
}

// ----------------------------------------------------
// Toast Notification Alerts
// ----------------------------------------------------
function showToast(message, type = 'info') {
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  
  let icon = '<i class="fa-solid fa-circle-info"></i>';
  if (type === 'success') icon = '<i class="fa-solid fa-circle-check"></i>';
  if (type === 'error') icon = '<i class="fa-solid fa-circle-exclamation"></i>';
  
  toast.innerHTML = `
    ${icon}
    <span>${message}</span>
  `;
  
  els.toastContainer.appendChild(toast);
  
  setTimeout(() => {
    toast.classList.add('fade-out');
    toast.addEventListener('animationend', () => {
      toast.remove();
    });
  }, 4000);
}

// Check browser File System Access support and warn if run under file:// protocol
function checkSecurityContext() {
  if (!window.showDirectoryPicker && window.location.protocol === 'file:') {
    alert("Warning: Browsing files and directories is not supported when opening HTML files directly from local folders (file:// protocol) due to browser security restrictions.\n\nPlease start the server using Start-App.bat and load http://localhost:8080/ in your browser.");
    addLog("Warning: Security context invalid. Opened via file:// protocol.", "error");
  }
}

// ─────────────────────────────────────────────────────────────
//  APPLICATION STARTUP — show splash, gate on mode selection
// ─────────────────────────────────────────────────────────────
function appStartup() {
  // The splash is visible by default (no display:none on the overlay in HTML)
  // Keyboard accessibility: Enter/Space on splash cards
  document.querySelectorAll('.splash-card').forEach(card => {
    card.addEventListener('keydown', e => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        card.click();
      }
    });
  });

  // Wire the Change Mode button in header
  const btnChangeMode = document.getElementById('btnChangeMode');
  if (btnChangeMode) {
    btnChangeMode.addEventListener('click', returnToModeSelector);
  }

  // Initialize Wi-Fi Camera Tool and live status
  initCameraIngest();

  // Initialize Mobile Customer Ingest & QR Monitor
  initMobileUploads();

  checkSecurityContext();
}

// ─────────────────────────────────────────────────────────────
//  MODE SELECTION
// ─────────────────────────────────────────────────────────────
function selectMode(mode) {
  appMode = mode;

  // Hide splash
  const overlay = document.getElementById('modeSelectorOverlay');
  if (overlay) overlay.classList.add('hidden');

  // Update header
  updateHeaderForMode(mode);

  if (mode === 'studio') {
    document.getElementById('studioPro-workspace').style.display = '';
    document.getElementById('eventMode-workspace').style.display = 'none';
    // Initialize Studio Pro if not already done
    if (!appInitialized) {
      init();
      appInitialized = true;
    }
  } else if (mode === 'event') {
    document.getElementById('studioPro-workspace').style.display = 'none';
    document.getElementById('eventMode-workspace').style.display = '';
    initEventMode();
  }
}

// Track whether Studio Pro has been initialized
let appInitialized = false;

function returnToModeSelector() {
  // Stop event polling if running
  if (evtPollTimer) { clearInterval(evtPollTimer); evtPollTimer = null; }

  // Hide workspaces
  document.getElementById('studioPro-workspace').style.display = 'none';
  document.getElementById('eventMode-workspace').style.display = 'none';

  // Show splash
  const overlay = document.getElementById('modeSelectorOverlay');
  if (overlay) overlay.classList.remove('hidden');

  // Reset header
  const badge = document.getElementById('modeBadge');
  const btn   = document.getElementById('btnChangeMode');
  if (badge) badge.style.display = 'none';
  if (btn)   btn.style.display   = 'none';

  appMode = null;
}

function updateHeaderForMode(mode) {
  const badge    = document.getElementById('modeBadge');
  const badgeIcon = document.getElementById('modeBadgeIcon');
  const badgeText = document.getElementById('modeBadgeText');
  const btn      = document.getElementById('btnChangeMode');

  if (!badge) return;

  badge.style.display = 'inline-flex';
  if (btn) btn.style.display = 'inline-flex';

  if (mode === 'studio') {
    badge.className = 'mode-badge mode-badge-studio';
    if (badgeIcon) badgeIcon.className = 'fa-solid fa-camera-retro';
    if (badgeText) badgeText.textContent = 'STUDIO PRO';
  } else {
    badge.className = 'mode-badge mode-badge-event';
    if (badgeIcon) badgeIcon.className = 'fa-solid fa-qrcode';
    if (badgeText) badgeText.textContent = 'EVENT KIOSK';
  }
}

// ─────────────────────────────────────────────────────────────
//  EVENT KIOSK MODE ENGINE
// ─────────────────────────────────────────────────────────────
function initEventMode() {
  evtSessionPrinted = 0;
  eventQueue = [];
  updateEvtStats();

  // Wire event-mode DOM listeners
  setupEventModeListeners();

  // Fetch local IP → build URL → generate QR
  fetchLocalIPAndGenerateQR();

  // Start polling for incoming customer photos
  startEvtQueuePoll();

  addEvtLog('Event Kiosk initialized. Waiting for QR scans...', 'info');
}

function setupEventModeListeners() {
  const evtPaperCh = document.getElementById('evtPaperChannel');
  if (evtPaperCh) {
    evtPaperCh.addEventListener('change', e => {
      evtActiveChannel = e.target.value;
      addEvtLog(`Paper channel → ${evtActiveChannel}`, 'info');
    });
  }

  const evtTplInput = document.getElementById('evtTemplateInput');
  if (evtTplInput) evtTplInput.addEventListener('change', handleEvtTemplateUpload);

  const evtRemoveTpl = document.getElementById('evtBtnRemoveTemplate');
  if (evtRemoveTpl) evtRemoveTpl.addEventListener('click', removeEvtTemplate);

  const evtClear = document.getElementById('evtBtnClearSession');
  if (evtClear) evtClear.addEventListener('click', clearEvtSession);

  // QR URL click → copy to clipboard
  const evtQRUrl = document.getElementById('evtQRUrl');
  if (evtQRUrl) {
    evtQRUrl.addEventListener('click', () => {
      if (evtLocalUrl) {
        navigator.clipboard.writeText(evtLocalUrl).then(() => {
          evtQRUrl.style.color = 'var(--success)';
          setTimeout(() => { evtQRUrl.style.color = ''; }, 1200);
        });
      }
    });
  }
}

// ── QR Code Generation ───────────────────────────────────────
async function fetchLocalIPAndGenerateQR() {
  try {
    const resp = await fetch('/api/info');
    const info = await resp.json();
    const ip   = info.ip || 'localhost';
    const port = info.port || 8080;
    evtLocalUrl = `http://${ip}:${port}/customer`;
    generateQRCode(evtLocalUrl);
    const el = document.getElementById('evtQRUrl');
    if (el) el.textContent = evtLocalUrl;

    // Update target printer indicator in Kiosk sidebar
    const pNameEl = document.getElementById('evtPrinterName');
    if (pNameEl) {
      if (info.ask300Sdk) {
        pNameEl.textContent = 'FUJIFILM ASK-300 (SDK Direct)';
      } else if (info.defaultPrinter) {
        pNameEl.textContent = info.defaultPrinter + ' (Windows Default)';
      } else {
        pNameEl.textContent = 'Windows Default Connected Printer';
      }
    }
  } catch {
    // Fallback: use localhost
    evtLocalUrl = `http://localhost:8080/customer`;
    generateQRCode(evtLocalUrl);
    const el = document.getElementById('evtQRUrl');
    if (el) el.textContent = evtLocalUrl + ' (localhost fallback)';
    addEvtLog('Could not fetch local IP — using localhost fallback. Ensure device is on same WiFi.', 'warning');
  }
}

function generateQRCode(url) {
  const container = document.getElementById('evtQRContainer');
  if (!container) return;
  container.innerHTML = '';

  if (typeof QRCode === 'undefined') {
    container.innerHTML = '<div class="evt-qr-placeholder">QR library not loaded.<br>Check internet connection.</div>';
    return;
  }

  evtQRInstance = new QRCode(container, {
    text: url,
    width: 200,
    height: 200,
    colorDark: '#000000',
    colorLight: '#ffffff',
    correctLevel: QRCode.CorrectLevel.M
  });
}

function refreshQRCode() {
  const container = document.getElementById('evtQRContainer');
  if (container) container.innerHTML = '<div class="evt-qr-placeholder"><i class="fa-solid fa-spinner fa-spin"></i><br>Refreshing...</div>';
  fetchLocalIPAndGenerateQR();
}

// ── Queue Polling ────────────────────────────────────────────
function startEvtQueuePoll() {
  if (evtPollTimer) clearInterval(evtPollTimer);
  evtPollTimer = setInterval(pollEvtQueue, 2500);
}

async function pollEvtQueue() {
  if (appMode !== 'event') return;
  try {
    const resp = await fetch('/api/event-queue');
    if (!resp.ok) return;
    const serverQueue = await resp.json();

    // Find genuinely new items (not already in local eventQueue)
    const existingIds = new Set(eventQueue.map(i => i.id));
    const newItems = serverQueue.filter(si => !existingIds.has(si.id));

    newItems.forEach(item => {
      item.status = 'pending';
      item.editParams = { brightness: 0, contrast: 0, saturation: 0 };
      eventQueue.push(item);
      addEvtLog(`Photo received from customer — ID: ${item.id.slice(0,8)}`, 'success');

      // Auto-print if toggle is ON
      const autoPrint = document.getElementById('evtAutoPrint');
      if (autoPrint && autoPrint.checked) {
        setTimeout(() => printEvtItem(item.id), 400);
      }
    });

    if (newItems.length > 0) {
      updateEvtStats();
      renderEvtQueue();
    }
  } catch { /* server may not be running yet */ }
}

// ── Queue Rendering ──────────────────────────────────────────
function renderEvtQueue() {
  const grid  = document.getElementById('evtQueueGrid');
  const empty = document.getElementById('evtQueueEmpty');
  const badge = document.getElementById('evtQueueBadge');

  const pending = eventQueue.filter(i => i.status !== 'done');

  if (!grid || !empty) return;

  if (pending.length === 0) {
    grid.style.display  = 'none';
    empty.style.display = 'flex';
    if (badge) badge.style.display = 'none';
    return;
  }

  grid.style.display  = '';
  empty.style.display = 'none';
  if (badge) { badge.style.display = 'inline'; badge.textContent = pending.length; }

  // Build card HTML for each pending item
  grid.innerHTML = pending.map(item => {
    const ep  = item.editParams;
    const bri = ep.brightness || 0;
    const con = ep.contrast   || 0;
    const sat = ep.saturation || 0;
    const filterCss = `brightness(${1 + bri/100}) contrast(${1 + con/100}) saturate(${1 + sat/100})`;
    const timeLabel = new Date(item.timestamp).toLocaleTimeString([], { hour:'2-digit', minute:'2-digit' });
    const isPrinting = item.status === 'printing';

    return `
      <div class="evt-photo-card" id="evtCard-${item.id}">
        <div class="evt-card-header">
          <span class="evt-card-meta"><i class="fa-solid fa-mobile-screen"></i> ${timeLabel}</span>
          <span class="evt-card-status ${isPrinting ? 'evt-status-printing' : 'evt-status-pending'}">
            ${isPrinting ? 'Printing...' : 'Ready'}
          </span>
        </div>
        <div class="evt-card-thumb-wrap">
          <img class="evt-card-thumb" id="evtThumb-${item.id}"
               src="${item.imageData}"
               style="filter: ${filterCss};"
               alt="Customer photo">
        </div>
        <div class="evt-card-adjustments">
          <div class="evt-adj-row">
            <span class="evt-adj-label">Brightness</span>
            <input type="range" class="evt-adj-slider" min="-50" max="50" value="${bri}"
              oninput="updateEvtAdjustment('${item.id}','brightness',this.value,this)">
            <span class="evt-adj-val">${bri >= 0 ? '+' : ''}${bri}</span>
          </div>
          <div class="evt-adj-row">
            <span class="evt-adj-label">Contrast</span>
            <input type="range" class="evt-adj-slider" min="-50" max="50" value="${con}"
              oninput="updateEvtAdjustment('${item.id}','contrast',this.value,this)">
            <span class="evt-adj-val">${con >= 0 ? '+' : ''}${con}</span>
          </div>
          <div class="evt-adj-row">
            <span class="evt-adj-label">Saturation</span>
            <input type="range" class="evt-adj-slider" min="-50" max="50" value="${sat}"
              oninput="updateEvtAdjustment('${item.id}','saturation',this.value,this)">
            <span class="evt-adj-val">${sat >= 0 ? '+' : ''}${sat}</span>
          </div>
        </div>
        <div class="evt-card-footer">
          <button class="evt-btn-print" onclick="printEvtItem('${item.id}')" ${isPrinting ? 'disabled' : ''}>
            <i class="fa-solid fa-print"></i> Print
          </button>
          <button class="evt-btn-reject" onclick="rejectEvtItem('${item.id}')" ${isPrinting ? 'disabled' : ''}>
            <i class="fa-solid fa-xmark"></i>
          </button>
        </div>
      </div>`;
  }).join('');
}

function updateEvtAdjustment(id, param, value, sliderEl) {
  const item = eventQueue.find(i => i.id === id);
  if (!item) return;
  item.editParams[param] = parseInt(value);

  // Update value label next to slider
  const valEl = sliderEl.nextElementSibling;
  if (valEl) valEl.textContent = (parseInt(value) >= 0 ? '+' : '') + value;

  // Live preview on thumbnail via CSS filter
  const thumb = document.getElementById(`evtThumb-${id}`);
  if (thumb) {
    const ep = item.editParams;
    thumb.style.filter = `brightness(${1 + ep.brightness/100}) contrast(${1 + ep.contrast/100}) saturate(${1 + ep.saturation/100})`;
  }
}

// ── Print Event Item ─────────────────────────────────────────
async function printEvtItem(id) {
  const item = eventQueue.find(i => i.id === id);
  if (!item || item.status === 'printing') return;

  item.status = 'printing';
  renderEvtQueue();
  addEvtLog(`Printing photo ${id.slice(0,8)}...`, 'info');

  try {
    // Load image into canvas
    const img = await new Promise((res, rej) => {
      const i = new Image();
      i.onload = () => res(i);
      i.onerror = rej;
      i.src = item.imageData;
    });

    // Channel dimensions: long side is always Width (6"), short side is Height (4")
    const channel = paperChannels[evtActiveChannel] || paperChannels['6x4'];
    const chLong = Math.max(channel.w, channel.h);
    const chShort = Math.min(channel.w, channel.h);
    const targetRatio = chLong / chShort; // e.g. 6/4 = 1.5

    // Automatically orient image so long side aligns with the 6-inch side:
    const orientedCanvas = getOrientedCanvas(img, evtActiveChannel);
    const srcW = orientedCanvas.width;
    const srcH = orientedCanvas.height;

    // Crop to target channel ratio (3:2 for 6x4)
    const ep = item.editParams;
    const crop = getDefaultCropForRatio(srcW, srcH, targetRatio);
    const cX = Math.round(crop.x * srcW);
    const cY = Math.round(crop.y * srcH);
    const cW = Math.max(1, Math.round(crop.w * srcW));
    const cH = Math.max(1, Math.round(crop.h * srcH));

    const canvas = document.createElement('canvas');
    canvas.width  = cW;
    canvas.height = cH;
    const ctx = canvas.getContext('2d');

    // Draw cropped image
    ctx.drawImage(orientedCanvas, cX, cY, cW, cH, 0, 0, cW, cH);

    // Apply brightness / contrast / saturation via pixel manipulation
    applyEvtAdjustmentsToCtx(ctx, cW, cH, ep);

    // Apply PNG template overlay if loaded
    if (evtTemplateImage) {
      ctx.save();
      ctx.globalAlpha = 1.0;
      ctx.drawImage(evtTemplateImage, 0, 0, cW, cH);
      ctx.restore();
    }

    // Encode to JPEG
    const blob = await new Promise(res => canvas.toBlob(res, 'image/jpeg', 0.93));
    const reader = new FileReader();
    reader.onloadend = async () => {
      const base64 = reader.result;
      try {
        const resp = await fetch('/api/print', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            filename: `event_${id.slice(0,8)}.jpg`,
            qty: 1,
            image: base64,
            eventMode: true,
            eventId: id,
            printDestination: 'direct',
            channelW: Math.round(chLong * 25.4),
            channelH: Math.round(chShort * 25.4),
            channelKey: evtActiveChannel
          })
        });
        const data = await resp.json();
        if (resp.ok && data.status === 'success') {
          // Remove from local queue + update counter
          eventQueue = eventQueue.filter(i => i.id !== id);
          evtSessionPrinted++;
          updateEvtStats();
          renderEvtQueue();
          const printDetail = data.details || 'Sent to printer';
          addEvtLog(`✓ Printed — photo ${id.slice(0,8)} (${printDetail}). Privacy: image deleted.`, 'success');
          // Acknowledge to server (delete temp data)
          fetch('/api/event-ack', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ id })
          }).catch(() => {});
        } else {
          throw new Error(data.message || 'Print failed');
        }
      } catch (err) {
        item.status = 'pending';
        renderEvtQueue();
        addEvtLog(`Print failed for ${id.slice(0,8)}: ${err.message}`, 'error');
      }
    };
    reader.readAsDataURL(blob);

  } catch (err) {
    item.status = 'pending';
    renderEvtQueue();
    addEvtLog(`Error processing ${id.slice(0,8)}: ${err.message}`, 'error');
  }
}

// ── Reject Event Item ────────────────────────────────────────
function rejectEvtItem(id) {
  eventQueue = eventQueue.filter(i => i.id !== id);
  updateEvtStats();
  renderEvtQueue();
  addEvtLog(`Photo ${id.slice(0,8)} rejected — removed from queue.`, 'warning');
  // Tell server to discard
  fetch('/api/event-ack', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ id })
  }).catch(() => {});
}

// ── Event Mode Adjustments (pixel-level, no auto-profile) ────
function applyEvtAdjustmentsToCtx(ctx, w, h, ep) {
  const bri = parseFloat(ep.brightness) || 0;
  const con = parseFloat(ep.contrast)   || 0;
  const sat = parseFloat(ep.saturation) || 0;

  if (bri === 0 && con === 0 && sat === 0) return;

  const imgData = ctx.getImageData(0, 0, w, h);
  const data = imgData.data;
  const len  = data.length;

  const briOffset = bri * 2.55;           // -50..+50 → -127..+127
  const conFactor = (259 * (con * 2.55 + 255)) / (255 * (259 - con * 2.55));
  const satFactor = (sat + 50) / 50;

  for (let i = 0; i < len; i += 4) {
    let r = data[i], g = data[i+1], b = data[i+2];

    // Brightness
    r += briOffset; g += briOffset; b += briOffset;

    // Contrast
    if (con !== 0) {
      r = conFactor * (r - 128) + 128;
      g = conFactor * (g - 128) + 128;
      b = conFactor * (b - 128) + 128;
    }

    // Saturation
    if (sat !== 0) {
      const lum = 0.299 * r + 0.587 * g + 0.114 * b;
      r = lum + (r - lum) * satFactor;
      g = lum + (g - lum) * satFactor;
      b = lum + (b - lum) * satFactor;
    }

    data[i]   = Math.max(0, Math.min(255, r));
    data[i+1] = Math.max(0, Math.min(255, g));
    data[i+2] = Math.max(0, Math.min(255, b));
  }
  ctx.putImageData(imgData, 0, 0);
}

// ── Event Stats & Helpers ────────────────────────────────────
function updateEvtStats() {
  const printed = document.getElementById('evtStatPrinted');
  const queue   = document.getElementById('evtStatQueue');
  if (printed) printed.textContent = evtSessionPrinted;
  if (queue)   queue.textContent   = eventQueue.filter(i => i.status !== 'done').length;
}

function addEvtLog(msg, type = 'info') {
  const panel = document.getElementById('evtLogPanel');
  if (!panel) return;
  const now = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  const typeClass = { success: 'log-entry-success', error: 'log-entry-error', warning: 'log-entry-warning', info: 'log-entry-info' }[type] || 'log-entry-info';
  const el = document.createElement('div');
  el.className = 'log-entry';
  el.innerHTML = `<span class="log-time">[${now}]</span><span class="${typeClass}">${msg}</span>`;
  panel.appendChild(el);
  panel.scrollTop = panel.scrollHeight;
}

function clearEvtSession() {
  if (!confirm('Clear all pending photos from the queue? This will remove them without printing.')) return;
  // Acknowledge all to server
  eventQueue.forEach(item => {
    fetch('/api/event-ack', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: item.id })
    }).catch(() => {});
  });
  eventQueue = [];
  evtSessionPrinted = 0;
  updateEvtStats();
  renderEvtQueue();
  addEvtLog('Session cleared.', 'warning');
}

// ── Event Mode Template Overlay ──────────────────────────────
function handleEvtTemplateUpload(e) {
  const file = e.target.files[0];
  if (!file) return;
  const url = URL.createObjectURL(file);
  const img = new Image();
  img.onload = () => {
    evtTemplateImage = img;
    const block = document.getElementById('evtTemplatePreviewBlock');
    const thumb = document.getElementById('evtTemplateThumbnail');
    const name  = document.getElementById('evtTemplateName');
    if (block) block.style.display = 'flex';
    if (thumb) thumb.src = url;
    if (name)  name.textContent = file.name;
    addEvtLog(`Template overlay loaded: ${file.name}`, 'success');
  };
  img.src = url;
}

function removeEvtTemplate() {
  evtTemplateImage = null;
  const block = document.getElementById('evtTemplatePreviewBlock');
  const input = document.getElementById('evtTemplateInput');
  if (block) block.style.display = 'none';
  if (input) input.value = '';
  addEvtLog('Template overlay removed.', 'info');
}

// ─────────────────────────────────────────────────────────────
//  SINGLE-RUN STARTUP HOOK
// ─────────────────────────────────────────────────────────────
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', appStartup);
} else {
  appStartup();
}

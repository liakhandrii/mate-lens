# Mate Lens - Repository Overview for Amazon Q

## Project Summary
**Mate Lens** is an iOS SwiftUI application that provides real-time camera-based text recognition and translation. The app captures photos, uses Google ML Kit for OCR (Optical Character Recognition), and displays translated text overlaid on the original image with perspective-correct positioning.

## Core Architecture

### Main Application Structure
- **Platform**: iOS 14.0+
- **Framework**: SwiftUI with UIKit integration
- **Language**: Swift
- **Dependencies**: CocoaPods-managed (Google ML Kit, SwiftyJSON)

### Key Components

#### 1. App Entry Point
- **File**: `MateCameraFixApp.swift`
- **Purpose**: Main app entry point using SwiftUI's `@main` attribute
- **Structure**: Simple WindowGroup containing ContentView

#### 2. Main Interface (`ContentView.swift`)
- **Primary View**: Main camera interface with capture functionality
- **Key Features**:
  - Real-time camera preview
  - Photo capture button with loading states
  - Debug mode toggle (DEBUG builds only)
  - Navigation to text overlay view
  - Error handling and progress indicators
- **State Management**: Uses `@StateObject` for camera and text recognition services
- **Navigation**: NavigationStack with programmatic navigation to overlay view

#### 3. Camera Management (`CameraManager.swift`)
- **Purpose**: Handles all camera operations using AVFoundation
- **Key Features**:
  - Camera session setup and management
  - Photo capture with completion handlers
  - Error handling with custom `CameraError` enum
  - Memory management with proper session cleanup
- **Architecture**: ObservableObject with published properties for SwiftUI integration

#### 4. Text Recognition (`TextRecognitionService.swift`)
- **Purpose**: OCR processing using Google ML Kit
- **Key Features**:
  - Text recognition from captured images
  - Batch translation integration
  - Word-level data extraction with positioning
  - Error handling and processing states
- **Data Flow**: Processes images → extracts text → translates → provides structured data

#### 5. Text Overlay System (`PerspectiveTextView.swift`)
- **Purpose**: Displays translated text overlaid on images with correct perspective
- **Key Features**:
  - Perspective-correct text positioning
  - Caching system for performance
  - Debug visualization modes
  - Adaptive font sizing
  - Content type detection and styling

### Data Models (`Models.swift`)

#### WordData
```swift
struct WordData {
    let text: String
    let translatedText: String?
    let frame: CGRect
    let cornerPoints: [CGPoint]?
}
```

#### ContentType Enum
- Categorizes text (number, date, price, productName, regular)
- Provides styling information (colors, font weights)

#### TransformedTextItem
- Processed text data for rendering
- Includes positioning, styling, and debug information

### Translation System

#### Current Implementation
- **File**: `TranslationService.swift`
- **Status**: Stub implementation (returns original text)
- **Purpose**: Placeholder for translation functionality

#### Advanced Translation Library (`lib/translation/`)
- **TranslationManager.swift**: Manages multiple translation providers
- **GoogleTranslate.swift**: Google Translate API v1 implementation
- **GoogleTranslateV2.swift**: Google Translate API v2 implementation
- **TranslationProvider.swift**: Protocol for translation services
- **Status**: Complete implementation but not integrated with main app

### Utility Functions (`Utilities.swift`)

#### Text Processing
- `detectContentType()`: Categorizes text using regex patterns
- `optimizeText()`: Corrects common OCR errors
- `selectAdaptiveFont()`: Chooses appropriate fonts based on content

#### Image Processing
- `normalize()`: Handles image orientation correction

### UI Components

#### CameraView (`CameraView.swift`)
- UIViewRepresentable wrapper for camera preview
- Integrates AVFoundation with SwiftUI

#### PerspectiveTextView
- Custom UIView for rendering text overlays
- Handles coordinate transformations
- Supports debug visualization

## Dependencies (Podfile)

### Core Dependencies
- **GoogleMLKit/TextRecognition**: OCR functionality
- **SwiftyJSON**: JSON parsing for translation services

### Transitive Dependencies
- Google ML Kit ecosystem (MLKitCommon, MLKitVision, etc.)
- Google utilities and networking components
- nanopb for protocol buffers

## Project Configuration

### Build System
- **Xcode Project**: `MateCameraFix.xcodeproj`
- **Workspace**: `MateCameraFix.xcworkspace` (CocoaPods integration)
- **Minimum iOS**: 14.0
- **Architecture**: Universal (supports all iOS devices)

### Git Configuration
- **Ignored Files**: `.DS_Store`, `xcuserdata/`
- **Repository**: Git-managed with standard iOS exclusions

## Key Features

### 1. Real-time Camera
- Live camera preview
- Photo capture with AVFoundation
- Proper session management and cleanup

### 2. Text Recognition
- Google ML Kit OCR integration
- Word-level text extraction
- Bounding box and corner point detection
- Error handling and validation

### 3. Translation (Planned)
- Multiple translation provider support
- Batch translation capabilities
- Fallback provider system

### 4. Perspective Text Overlay
- Accurate text positioning on images
- Perspective-correct rendering
- Content-aware styling
- Performance optimization with caching

### 5. Debug Features
- Visual debugging for text positioning
- Performance metrics
- Development-only debug controls

## Development Workflow

### Debug Mode
- Enabled only in DEBUG builds
- Provides visual debugging for text positioning
- Shows text detection statistics
- Toggle-able debug overlays

### Error Handling
- Comprehensive error types for camera operations
- User-friendly error messages
- Graceful degradation for failed operations

### Performance Considerations
- Caching system for text transformations
- Asynchronous image processing
- Memory management for camera sessions
- Efficient coordinate transformations

## Code Organization

### File Structure
```
MateCameraFix/
├── MateCameraFixApp.swift          # App entry point
├── ContentView.swift               # Main interface
├── CameraManager.swift             # Camera operations
├── CameraView.swift                # Camera UI component
├── TextRecognitionService.swift    # OCR processing
├── PerspectiveTextView.swift       # Text overlay rendering
├── Models.swift                    # Data models
├── Utilities.swift                 # Helper functions
├── TranslationService.swift        # Translation stub
└── lib/translation/                # Advanced translation system
    ├── TranslationManager.swift
    ├── GoogleTranslate.swift
    ├── GoogleTranslateV2.swift
    └── TranslationProvider.swift
```

### Architecture Patterns
- **MVVM**: SwiftUI with ObservableObject view models
- **Delegation**: AVFoundation camera delegate pattern
- **Protocol-Oriented**: Translation provider abstraction
- **Reactive**: Combine framework for data flow

## Integration Points

### Google ML Kit
- Text recognition with bounding boxes
- Multi-language support
- On-device processing

### AVFoundation
- Camera session management
- Photo capture
- Preview layer integration

### SwiftUI + UIKit
- UIViewRepresentable for camera preview
- Custom UIView for text rendering
- Seamless integration between frameworks

## Future Development Areas

### Translation Integration
- Connect advanced translation library to main app
- Implement provider fallback system
- Add language detection

### UI Enhancements
- Settings screen for language preferences
- History of captured/translated images
- Export functionality

### Performance Optimization
- Background processing for OCR
- Image compression strategies
- Memory usage optimization

## Technical Debt

### Current Issues
1. Translation service is stubbed out
2. Advanced translation library not integrated
3. Limited error recovery mechanisms
4. No persistent storage for results

### Recommended Improvements
1. Integrate full translation system
2. Add comprehensive unit tests
3. Implement result caching/storage
4. Add accessibility features
5. Optimize memory usage patterns

## Testing Structure

### Current Test Files
- `MateCameraFixTests/`: Unit test placeholder
- `MateCameraFixUITests/`: UI test placeholder
- **Status**: Minimal test coverage

### Recommended Test Coverage
- Camera manager functionality
- Text recognition accuracy
- Translation service integration
- UI interaction flows
- Error handling scenarios

This overview provides Amazon Q with comprehensive understanding of the Mate Lens codebase, enabling efficient navigation and assistance without requiring full repository scans for each interaction.

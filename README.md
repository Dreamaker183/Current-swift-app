# Current+ SwiftUI App

A comprehensive SwiftUI application designed for monitoring and managing power consumption, integrating with ThingSpeak for real-time data and device control. Features an interactive AI assistant for enhanced user experience.

## Key Features

*   **Dashboard:**
    *   Real-time power usage monitoring vs. predicted usage charts.
    *   Remaining balance gauge with visual indicators (Optimal, Good, Moderate, Low, Critical).
    *   Low balance notifications (< 15%) and power cut simulation warnings.
*   **Connected Devices:**
    *   Control connected devices (Light, Washing Machine, Smart TV) via the app interface.
    *   Device states (ON/OFF) are updated in ThingSpeak (Fields 7 & 8).
*   **Battery Monitor:**
    *   Detailed view of battery usage over the last 24 hours.
    *   Interactive 3D visualization of the battery system (using Spline/WebView).
    *   Displays Arduino Battery System status, charge percentage, solar production, and room temperature.
*   **AI Assistant:**
    *   Interactive chat interface for user queries.
    *   Natural language processing to control connected devices (Light, Washing Machine).
    *   Text-to-speech functionality for assistant responses (using AVFoundation).
    *   3D AI model visualization (using Spline/WebView).
*   **Power Plans:**
    *   View and select different power plans (Daily, Weekly, Monthly).
    *   Integration with Apple Pay for plan subscriptions (simulated).
*   **Preferences:**
    *   Toggle Dark Mode.
    *   Manage notification settings.
*   **Help & Support:**
    *   Access FAQs, contact options (Phone, Email, Live Chat).

## Technologies Used

*   **SwiftUI:** For building the user interface.
*   **Combine:** For handling asynchronous data fetching from ThingSpeak.
*   **Charts:** For displaying usage data.
*   **ThingSpeak API:** For fetching usage data, balance, temperature and controlling device states.
*   **AVFoundation:** For text-to-speech capabilities in the AI Assistant.
*   **WebKit:** For displaying interactive Spline 3D models.
*   **UserNotifications:** For sending local notifications (low balance, power cut).
*   **PassKit:** For Apple Pay integration (simulated).

## Setup

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/Dreamaker183/Current-swift-app.git
    cd Current-swift-app
    ```
2.  **Open in Xcode:** Open the `.xcodeproj` or `.xcworkspace` file.
3.  **ThingSpeak API Keys:** The application uses hardcoded ThingSpeak Channel ID, Read API Key, and Write API Key within `ContentView.swift`. Replace these with your own keys if using a different ThingSpeak channel.
    *   `channelID`: "2834155"
    *   `readKey`: "KXJYZHUQCKBVSJUO"
    *   `writeKey` (used in `sendDeviceLEDCommand`): "YCT2QXNYDWJOMK9B"
4.  **Build and Run:** Select a target simulator or physical device and run the application.

## Notes

*   The app uses hardcoded device IDs (1 for Light, 2 for Washing Machine) for control via the AI Assistant and ThingSpeak updates.
*   Ensure the necessary simulator runtime (e.g., iOS 18.0) is installed in Xcode if you encounter runtime availability errors.
*   The SplineRuntime framework dependency was replaced with WebKit for displaying Spline scenes.

## License and Usage

This project is provided without any license. All rights are reserved by the author. You are not permitted to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, or permit persons to whom the Software is furnished to do so, without explicit written permission from the author.

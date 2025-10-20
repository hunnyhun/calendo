# Stoa AI - iOS App

A Stoicism-focused personal development app that helps users build better habits and track their progress through AI-powered insights and daily reflections.

## Features

- Daily stoic quotes and reflections
- AI-powered habit tracking and suggestions
- Task management with stoic principles
- Calendar integration
- Chat interface for personalized guidance
- Multi-language support
- iOS Widget support

## Tech Stack

- Swift UI
- Firebase (Authentication, Firestore, Cloud Functions)
- Node.js (Backend)
- TypeScript

## Setup Requirements

1. Xcode 14.0 or later
2. iOS 15.0+ deployment target
3. Node.js 16.x or later (for backend)
4. Firebase project setup

## Getting Started

1. Clone the repository
2. Set up Firebase:
   - Create a new Firebase project
   - Download `GoogleService-Info.plist` from Firebase Console
   - Place it in the `Stoa AI/Stoa AI/` directory
3. Install backend dependencies:
   ```bash
   cd backend/functions-v2
   npm install
   ```
4. Open `Stoa AI.xcodeproj` in Xcode
5. Build and run the project

## Environment Setup

The following files are required but not included in the repository for security:

- `GoogleService-Info.plist` (Firebase configuration)
- `.env` files for backend configuration

Contact the project maintainers to obtain these files.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is proprietary software. All rights reserved.

## Support

For support, please visit our [support page](support.md) or contact the development team.

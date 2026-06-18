# Project Report

* Report PDF: [Open the report](./SreshthTiwari_Report.pdf)

# Getting Started

This project is my own implementation of a portrait imaging app specifically for iOS. I highly recommend reading [this report](./SreshthTiwari_Report.pdf) that I wrote for details and results. I've detailed steps on running the app below:

## Prerequisites

* Node.js
* npm or Yarn
* Android Studio for Android
* Xcode for iOS on macOS
* CocoaPods for iOS dependencies

## Install Dependencies

From the root of the project, install the packages:

```sh
npm install
```

## Start the Metro Server

Metro is the JavaScript bundler used by React Native. Start it with:

```sh
npm start
```

## Run the App on iOS

If you are using iOS, install CocoaPods dependencies first:

```sh
bundle install
bundle exec pod install
```

Then run:

```sh
npm run ios
```

This requires macOS and Xcode.

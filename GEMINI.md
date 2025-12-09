# NetBar Ops Project

## Project Overview

This project is a comprehensive solution for managing netbars (internet cafes). It is a full-stack application consisting of a backend API, a web-based management dashboard, and a cross-platform client application.

The repository is structured as a monorepo containing:

*   **Backend API (`netbar-ops-api`)**: Written in **Go**, providing RESTful services, database management, and authentication.
*   **Web Dashboard (`netbar-ops-vue`)**: Built with **Vue.js**, **TypeScript**, and **Tailwind CSS**, offering a modern interface for administrators to manage terminals, users, and configurations.
*   **Client App (`netbar_ops_flutter`)**: A **Flutter** application (likely targeting Windows/Desktop and potentially mobile) for monitoring or terminal-side interaction.

## Directory Structure

*   `netbar-ops-api/`: The Go backend server.
*   `netbar-ops-vue/`: The Vue.js frontend web application.
*   `netbar_ops_flutter/`: The Flutter cross-platform client application.

---

## 1. Backend API (`netbar-ops-api`)

**Technology Stack:**
*   **Language:** Go (1.21+)
*   **Framework:** Gin Web Framework
*   **Database ORM:** GORM (supports SQLite and MySQL)
*   **Authentication:** JWT (JSON Web Tokens)

**Key Commands:**
*   **Run Server:**
    ```bash
    cd netbar-ops-api
    go run cmd/server/main.go
    ```
*   **Install Dependencies:**
    ```bash
    cd netbar-ops-api
    go mod download
    ```

**Development Notes:**
*   Configuration is likely handled via `config.yaml` or environment variables.
*   The `cmd/` directory contains the application entry points.
*   The `internal/` directory contains the core logic (handlers, models, middleware).

---

## 2. Web Dashboard (`netbar-ops-vue`)

**Technology Stack:**
*   **Framework:** Vue 3
*   **Language:** TypeScript
*   **Build Tool:** Vite
*   **Styling:** Tailwind CSS
*   **State/Logic:** VueUse, Axios
*   **Editor:** Monaco Editor

**Key Commands:**
*   **Install Dependencies:**
    ```bash
    cd netbar-ops-vue
    npm install
    ```
*   **Start Development Server:**
    ```bash
    cd netbar-ops-vue
    npm run dev
    ```
*   **Build for Production:**
    ```bash
    cd netbar-ops-vue
    npm run build
    ```

**Development Notes:**
*   The project follows a standard Vite + Vue structure.
*   API integration is likely handled in the `api/` directory (seen in file list).
*   Check `.env` files for API endpoint configuration.

---

## 3. Client App (`netbar_ops_flutter`)

**Technology Stack:**
*   **Framework:** Flutter (SDK ^3.10.3)
*   **State Management:** Flutter Riverpod
*   **Routing:** GoRouter
*   **Networking:** Dio
*   **Code Generation:** Freezed, JSON Serializable

**Key Commands:**
*   **Get Dependencies:**
    ```bash
    cd netbar_ops_flutter
    flutter pub get
    ```
*   **Run App (Debug):**
    ```bash
    cd netbar_ops_flutter
    flutter run
    ```
*   **Run Code Generation (Build Runner):**
    ```bash
    cd netbar_ops_flutter
    dart run build_runner build --delete-conflicting-outputs
    ```

**Development Notes:**
*   This app targets multiple platforms (Windows, Web, etc.).
*   It uses code generation extensively (Freezed, JSON Serializable), so remember to run the build runner after modifying models.

## General Workflow

1.  **Start the Backend:** Ensure the Go API is running first as both the Vue and Flutter apps likely depend on it.
2.  **Start the Frontend(s):** Run the Vue web dashboard or Flutter app depending on the feature you are working on.

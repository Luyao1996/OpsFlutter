# Repository Guidelines

## Project Structure & Module Organization
- `netbar-ops-api/`: Go backend (main entry in `cmd/server`, seed tools in `cmd/seed`, shared code under `internal/`, runtime config in `config.yaml`, file uploads in `uploads/`, sample data in `data/`).
- `netbar-ops-vue/`: Vue 3 + Vite + Tailwind frontend (`pages/`, `components/`, `layouts/`, shared utilities in `composables/`, API clients in `api/`).
- `netbar_ops_flutter/`: Flutter client (`lib/` app code, `assets/` for bundled resources, `test/` for widget/unit tests); supports web/desktop/mobile targets.
- Root assets live in `imgs/`; lockfiles (`package-lock.json`, `pubspec.lock`, `go.sum`) should stay committed.

## Build, Test, and Development Commands
- Backend: `cd netbar-ops-api && go run ./cmd/server` to start the API; `go test ./...` for all Go tests; `gofmt -w ./` before committing.
- Frontend: `cd netbar-ops-vue && npm install` once, then `npm run dev` (local), `npm run build` (production), `npm run preview` (serve build).
- Flutter: `cd netbar_ops_flutter && flutter pub get` once, `flutter run -d chrome` (web) or `flutter run` (default device), `flutter test` (all Dart tests), `flutter build apk` or `flutter build web` for releases.

## Coding Style & Naming Conventions
- Go: follow standard library patterns; keep packages under `internal/`; name handlers/services with clear intent (`UserService`, `AuthMiddleware`). Always `gofmt` and prefer `go vet` on changes.
- Vue: TypeScript everywhere; PascalCase for components, camelCase for composables and utilities; keep Tailwind classes in templates minimal—extract shared styles to `index.css` when repeated.
- Flutter: respect `analysis_options.yaml`; use PascalCase widgets, camelCase methods/fields; keep assets declared in `pubspec.yaml`.

## Testing Guidelines
- Place Go tests alongside code (`*_test.go`) and target packages with `go test ./internal/...` when changing internals.
- Vue currently has no test harness—if adding one, use Vitest and colocate specs under the same folder (`ComponentName.spec.ts`).
- Flutter tests belong in `test/`; prefer widget tests for UI and add golden references for visual changes when possible.

## Commit & Pull Request Guidelines
- Recent history favors short, task-focused messages; keep them imperative and scoped (e.g., `Add dashboard charts`, `Fix Flutter base URL`).
- In PRs: summarize scope, list key modules touched, link relevant issues, and include screenshots/GIFs for UI changes (Vue/Flutter). Note config expectations (e.g., `config.yaml` endpoints, seeded data) and manual steps taken.

## Security & Configuration Tips
- Keep secrets out of the repo; use `config.yaml` for local-only values and document defaults in the PR.
- Uploaded files (`uploads/`) and generated builds (`dist/`, Flutter `build/`) should stay untracked; verify `.gitignore` before adding new artifacts.

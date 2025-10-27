# Godot Driller

A Godot game project with automated web builds and PR previews.

## Development

This project uses Godot 4.5 for game development.

## GitHub Actions

The project includes automated web builds for every push and pull request.

### PR Preview Setup

The workflow uses **GitHub Pages** to deploy PR previews - no external services or tokens required!

**One-time setup:**

1. Go to your repository Settings
2. Navigate to Pages (left sidebar)
3. Under "Build and deployment":
   - Source: Deploy from a branch
   - Branch: `gh-pages` / `root`
4. Click Save

Once configured, every pull request will automatically:
- Build the web version
- Deploy it to `https://{username}.github.io/{repo}/pr-preview/pr-{number}/`
- Post a comment on the PR with a direct link to test the game

### How It Works

- **PR builds**: Deployed to `pr-preview/pr-{number}/` subdirectory on GitHub Pages
- **Main branch**: Deployed to the root of your GitHub Pages site
- **Automatic cleanup**: PR previews are removed when the PR is closed
- **Artifacts**: Web builds are also uploaded as artifacts (14-day retention)

### Manual Testing

If you prefer to test builds locally:

1. Download the artifact from the GitHub Actions run
2. Extract the zip file
3. Serve the files using a local web server:
   ```bash
   cd build/web
   python -m http.server 8000
   # or
   npx serve .
   ```
4. Open http://localhost:8000 in your browser

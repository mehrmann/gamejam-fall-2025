# Godot Driller

A Godot game project with automated web builds and PR previews.

## Development

This project uses Godot 4.5 for game development.

## GitHub Actions

The project includes automated web builds for every push and pull request.

### PR Preview Setup

To enable automatic PR previews, you need to set up a Surge token:

1. Install Surge CLI locally:
   ```bash
   npm install -g surge
   ```

2. Create a Surge account (if you don't have one):
   ```bash
   surge login
   ```

3. Get your Surge token:
   ```bash
   surge token
   ```

4. Add the token to your GitHub repository:
   - Go to your repository Settings
   - Navigate to Secrets and variables → Actions
   - Click "New repository secret"
   - Name: `SURGE_TOKEN`
   - Value: (paste your token from step 3)
   - Click "Add secret"

Once configured, every pull request will automatically:
- Build the web version
- Deploy it to `https://godot-driller-pr-{number}.surge.sh`
- Post a comment with a direct link to try the build

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

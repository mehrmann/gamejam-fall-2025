# Godot Driller

A Godot game project with automated web builds and PR previews.

## Development

This project uses Godot 4.5 for game development.

## GitHub Actions

The project includes automated web builds for every push and pull request.

### PR Preview Setup (GitHub Pages - Default)

The workflow is configured to use **GitHub Pages** for PR previews - no external services or tokens required!

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
- Comment on the PR with the preview link

**Note:** The PR preview action will automatically post a comment with the preview URL.

### Alternative Hosting Options

Want to use a different hosting service? Here are some alternatives:

#### Option 1: Netlify
Replace the "Deploy PR Preview" step with:
```yaml
- name: Deploy to Netlify
  if: github.event_name == 'pull_request'
  uses: nwtgck/actions-netlify@v3
  with:
    publish-dir: build/web
    production-deploy: false
    github-token: ${{ secrets.GITHUB_TOKEN }}
    enable-pull-request-comment: true
    enable-commit-comment: false
```
No secrets needed - uses GitHub token automatically.

#### Option 2: Cloudflare Pages
```yaml
- name: Deploy to Cloudflare Pages
  if: github.event_name == 'pull_request'
  uses: cloudflare/wrangler-action@v3
  with:
    apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
    accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
    command: pages deploy build/web --project-name=godot-driller
```
Requires: `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` secrets.

#### Option 3: Vercel
```yaml
- name: Deploy to Vercel
  if: github.event_name == 'pull_request'
  uses: amondnet/vercel-action@v25
  with:
    vercel-token: ${{ secrets.VERCEL_TOKEN }}
    vercel-org-id: ${{ secrets.VERCEL_ORG_ID }}
    vercel-project-id: ${{ secrets.VERCEL_PROJECT_ID }}
    working-directory: build/web
```
Requires: Vercel account and three secrets.

#### Option 4: Surge.sh
```yaml
- name: Deploy to Surge
  if: github.event_name == 'pull_request'
  run: |
    npm install -g surge
    surge build/web godot-driller-pr-${{ github.event.pull_request.number }}.surge.sh --token ${{ secrets.SURGE_TOKEN }}
```
Requires: `SURGE_TOKEN` secret (get with `surge token` command).

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

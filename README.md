# MacToys

Mac utilities inspired by Microsoft PowerToys. An independent project, not affiliated with Microsoft.

Requires macOS 14+ and Xcode 16+ (or its Command Line Tools).

To install, open Terminal and run:

```sh
xcode-select --install # Skip if developer tools are already installed.
```

Once the tools finish installing:

```sh
git clone https://github.com/MudassarZia/MacToys.git
cd MacToys
bash scripts/build-app.sh
open build
```

Drag **MacToys.app** from the folder that opens into **Applications**, then launch it. Grant Accessibility, Input Monitoring, or Screen Recording only when a tool needs it.

Early alpha; some macOS integrations are still being tested.

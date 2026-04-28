## Quick Start
Use this when you only need the shortest developer path.

```bash
cd $WORKSPACE_DIR

# Build qirp-sdk package
sudo python ./build-utils/ubuntu/build.py --build-kernel
sudo python ./build-utils/ubuntu/build.py --gen-debians --pack-image qirp-sdk

# Verify package outputs
tree debian_packages/oss/qirp-sdk/

# Check installed version on target
apt list --installed | grep qirp-sdk

# Upgrade on target
scp qirp-sdk*.deb <user>@<ip>:/opt
apt remove qirp-sdk
apt install qirp-sdk
```

## Build and Packaging On Host
### Full Robotics image build (with preinstall)
```bash
cd $WORKSPACE_DIR
sudo python ./build-utils/ubuntu/build.py --build-full-image
```

### Step-by-step build
```bash
sudo python ./build-utils/ubuntu/build.py --build-kernel
sudo python ./build-utils/ubuntu/build.py --gen-debians
sudo python ./build-utils/ubuntu/build.py --pack-image
```

### Build standalone `qirp-sdk` package only
```bash
sudo python ./build-utils/ubuntu/build.py --build-kernel
sudo python ./build-utils/ubuntu/build.py --gen-debians --pack-image qirp-sdk
```

Expected artifacts :
- `qirp-sdk_<version>_arm64.deb`
- `qirp-sdk_<version>.dsc`

Expected location:
- `debian_packages/oss/qirp-sdk/`

## SDK Upgrade Workflow On Target
The upgrade model uses native Ubuntu `apt/dpkg` behavior.

1. Check current package status on target.
```bash
apt list --installed | grep qirp-sdk
```
2. Push target version packages to the device (SSH or ADB flow).
```bash
scp qirp-sdk*.deb <user>@<ip>:/opt
```
3. Remove current package.
```bash
apt remove qirp-sdk
```
4. Install new package.
```bash
apt install qirp-sdk
```
5. Validate runtime and dependency state.

Notes:
- Upstream dependencies can be upgraded from official/upstream PPAs.

## Dependency Pickup Mechanism On Host
When adding new SDK dependencies, update `Depends` in `qirp-sdk` `debian/control`.

```debcontrol
Package: qirp-sdk
Architecture: arm64
Depends:
  ros-jazzy-existing-package,
  ros-jazzy-new-package,
  ...
```

Then rebuild the package:
```bash
sudo python ./build-utils/ubuntu/build.py --gen-debians --pack-image qirp-sdk
```

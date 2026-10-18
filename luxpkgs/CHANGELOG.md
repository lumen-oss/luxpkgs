# Changelog

## [0.5.1](https://github.com/lumen-oss/luxpkgs/compare/v0.5.0...v0.5.1) (2026-10-18)


### Bug Fixes

* allow dots (.) in package names ([17118c0](https://github.com/lumen-oss/luxpkgs/commit/17118c0dac3e04161ae45931ff087016a65146d4))

## [0.5.0](https://github.com/lumen-oss/luxpkgs/compare/v0.4.0...v0.5.0) (2026-10-17)


### Features

* implement user deletion ([#133](https://github.com/lumen-oss/luxpkgs/issues/133)) ([a79ee2d](https://github.com/lumen-oss/luxpkgs/commit/a79ee2dedf9d312bdd1611269ea195caf7562e48))
* use static TOTP secret in dev builds ([372ead1](https://github.com/lumen-oss/luxpkgs/commit/372ead1e6cdc76b2d7cacb5975d211b118405eb8))


### Bug Fixes

* **Dockerfile:** use pnpm ([0889323](https://github.com/lumen-oss/luxpkgs/commit/088932305915c8aa17079142373e16c6863bce73))
* **keys:** properly colour toggles in API creation menu ([4d9c7d5](https://github.com/lumen-oss/luxpkgs/commit/4d9c7d59dd55c13ae57af56531172533b840a6e0))

## [0.4.0](https://github.com/lumen-oss/luxpkgs/compare/v0.3.0...v0.4.0) (2026-10-17)


### ⚠ BREAKING CHANGES

* rename project to `luxpkgs`

### Features

* **settings/2fa:** rework the backup codes display ([f5d24ae](https://github.com/lumen-oss/luxpkgs/commit/f5d24aeea0ec12d7c072b4b12c73c755c99ab7c5))
* **setup_totp:** slightly improve UI consistency ([990ab4e](https://github.com/lumen-oss/luxpkgs/commit/990ab4ebf9945350b53b4c3941e7aefb72a1b639))


### Bug Fixes

* **2fa:** make token validation entirely server-side to plug all security holes ([912c313](https://github.com/lumen-oss/luxpkgs/commit/912c313e7f54377832dc240c06884b9189da2a2a))
* **a11y:** icon hiding, label association, keyboard nav, skip link ([ccaa32b](https://github.com/lumen-oss/luxpkgs/commit/ccaa32bd2ca0f32b2804ad8c7b6a2d970c0a189b))
* **home:** balance the hero tagline text wrap ([bfeb9ba](https://github.com/lumen-oss/luxpkgs/commit/bfeb9ba76a62b0e754a46c8f7445ae93fed6ac45))
* **luxpkgs:** improve light theme contrast ([4b05ac1](https://github.com/lumen-oss/luxpkgs/commit/4b05ac1f1e0dec152a6c551347ef678f94ef0383))
* **luxpkgs:** proper yellow color for light theme ([3ef55a6](https://github.com/lumen-oss/luxpkgs/commit/3ef55a67ab5c68d95b09397ebf6c1c3043d3daf2))
* **settings/2fa:** generate backup codes when two-factor authentication is set up ([fa94d98](https://github.com/lumen-oss/luxpkgs/commit/fa94d9815f86eec8e3560a7a4de13f82b98e5617))
* **settings/2fa:** modal behaviour ([a98bb3a](https://github.com/lumen-oss/luxpkgs/commit/a98bb3ade9dae8245bdefe56bccd94eef038a50a))
* **settings/2fa:** polish backup codes panel and modals ([ad886e8](https://github.com/lumen-oss/luxpkgs/commit/ad886e817324a13408053b1bd28e28d09c05d6ba))
* **settings/2fa:** round the 2FA and backup-codes panels ([5135445](https://github.com/lumen-oss/luxpkgs/commit/513544543a4d96f533821953dba08d834344e506))
* **totp/setup:** reuse the pending secret when a retry is submitted ([1a0bc73](https://github.com/lumen-oss/luxpkgs/commit/1a0bc73a26512d9df679d761f7585c65997dc3f4))
* **ui:** harden modal reset and close behavior ([9f74e8a](https://github.com/lumen-oss/luxpkgs/commit/9f74e8a888295cd9a7de5270ab407ef150f429de))


### Miscellaneous Chores

* release 0.4.0 ([bfc6dde](https://github.com/lumen-oss/luxpkgs/commit/bfc6ddedf0d79fb935dc394f0517b79db2ee222a))


### Code Refactoring

* rename project to `luxpkgs` ([1262e57](https://github.com/lumen-oss/luxpkgs/commit/1262e579b8920bf5f307c2c1f5eed58f681ab3d7))

## [0.3.0](https://github.com/lumen-oss/luxpkgs/compare/v0.2.0...v0.3.0) (2026-07-01)


### Features

* fix tests and fixtures ([9a330c4](https://github.com/lumen-oss/luxpkgs/commit/9a330c478f1efe7961c0a187cd8ff7bada42256a))
* luarocks API compatibility ([de5f759](https://github.com/lumen-oss/luxpkgs/commit/de5f759e9b03555be3d92634045f03c139e4678e))
* parse versions as true semver internally (with sorting in the UI) ([fd6d2dd](https://github.com/lumen-oss/luxpkgs/commit/fd6d2dde7b4e778ef2c378c30eb1f2481a0efa1e))
* rate limiting for APIs ([548ede0](https://github.com/lumen-oss/luxpkgs/commit/548ede095c9c85921f4ef2807107537368830374))
* render descriptions as Markdown ([da4cf46](https://github.com/lumen-oss/luxpkgs/commit/da4cf46874a116f60c1a3132e426f03f654592b4))


### Bug Fixes

* deny large rockspecs ([e868230](https://github.com/lumen-oss/luxpkgs/commit/e8682305e789c164c321e89fa335623c2d83b64d))
* proper path sanitization for rockspec paths ([49c3595](https://github.com/lumen-oss/luxpkgs/commit/49c359512181cc819804083e08b0b81e084cebda))
* use absolute filepath for rockspec locations so downloading works properly again ([2f51db8](https://github.com/lumen-oss/luxpkgs/commit/2f51db8469229fabcbdf88e96987ac43184a3fca))

## [0.2.0](https://github.com/lumen-oss/luxpkgs/compare/v0.1.1...v0.2.0) (2025-12-01)


### Features

* add LiveView pages transition ([77a526b](https://github.com/lumen-oss/luxpkgs/commit/77a526bc8e54b22adc5dfca7461ce1d562e6561f))
* improve mobile navbar UI/UX ([84f99dd](https://github.com/lumen-oss/luxpkgs/commit/84f99dd213e67047a866486b90fd6170249c9d29))
* **navbar:** add source button ([#81](https://github.com/lumen-oss/luxpkgs/issues/81)) ([4c203d8](https://github.com/lumen-oss/luxpkgs/commit/4c203d80e873f4cdb39daf2fa762b72b423f80e8))
* **navbar:** backdrop overlay, close on outside click, scroll lock, animations ([fb65e23](https://github.com/lumen-oss/luxpkgs/commit/fb65e23be862fef4fd9099033cc90da5b2f1c4e4))


### Bug Fixes

* **accounts:** proper OAuth identity resolution on private emails ([da345d3](https://github.com/lumen-oss/luxpkgs/commit/da345d345e924f9225ae09cb35d2d179e3a37691))
* **home:** make hero banner stay on top of the actions in mobile ([c9e1a59](https://github.com/lumen-oss/luxpkgs/commit/c9e1a59720c5c61e849565ed8ee8011d4f3e23ef))
* make the "Back to packages" link link to the package page ([662cc47](https://github.com/lumen-oss/luxpkgs/commit/662cc47e10287be0e7640b00abce286c775388cd))
* move lux hyperlink to static line ([6ae6f59](https://github.com/lumen-oss/luxpkgs/commit/6ae6f599c325b74849aac36ce3b490774c3ba4ab))
* **navbar:** properly call `/logout` endpoint ([7de76d7](https://github.com/lumen-oss/luxpkgs/commit/7de76d76518bd1743a6b9def223c415462456199))
* proper API keys header alignment on mobile ([f440f47](https://github.com/lumen-oss/luxpkgs/commit/f440f471a1a288079359b4751140f3a61a2d5ca5))
* use navigate for in-site live navigation links ([8ee97ff](https://github.com/lumen-oss/luxpkgs/commit/8ee97ffa80cf8e824d05dd4c1971a4c726cbaf8a)), closes [#71](https://github.com/lumen-oss/luxpkgs/issues/71)
* use p sigil for route verification ([0aa839f](https://github.com/lumen-oss/luxpkgs/commit/0aa839f7734769a0951bddfacefd289c198e8361))

## [0.1.1](https://github.com/lumen-oss/luxpkgs/compare/v0.1.0...v0.1.1) (2025-09-16)


### Bug Fixes

* restrict allowed package names ([2b6237f](https://github.com/lumen-oss/luxpkgs/commit/2b6237f3baaa1d905c491fca29f8301835721c46))
* rockspec uploads in production ([9423b91](https://github.com/lumen-oss/luxpkgs/commit/9423b916239e5fd78f0a5abafcbd8cbe2d420dfd))

## 0.1.0 (2025-09-16)


### ⚠ BREAKING CHANGES

* revamp landing page
* move `luxpkgs-rockspec-verifier` into the repository

### Features

* add buttons to the landing header below the search bar ([265bf9d](https://github.com/lumen-oss/luxpkgs/commit/265bf9daff5c0285e59c1558e8307de4f396657b))
* add download count for each release ([116f7cd](https://github.com/lumen-oss/luxpkgs/commit/116f7cdaf97cd147b8b5eed909c015112c0a7ba8))
* add download count for each release ([8db4a7f](https://github.com/lumen-oss/luxpkgs/commit/8db4a7f2b09b009a6d11649577978826405d93cc))
* add user count, fix broken links ([8497254](https://github.com/lumen-oss/luxpkgs/commit/84972548e196ac22c0f19a0da8c631e89b14a84e))
* donation page ([e6e3965](https://github.com/lumen-oss/luxpkgs/commit/e6e39658f0c12e09c89a66e9453fa0806d36d8a9))
* implement user settings page (WIP) ([1e344cd](https://github.com/lumen-oss/luxpkgs/commit/1e344cd4c26a8e7a55a9f0007165de2d9aae1534))
* minimal home adjustments, add links to landing buttons ([d470445](https://github.com/lumen-oss/luxpkgs/commit/d4704453fb4c4af6ad9d9eadaee58dcbfbd82268))
* move featured packages into their own component, small home fixes ([f91ac23](https://github.com/lumen-oss/luxpkgs/commit/f91ac23f3197570601900cc051047287144f2261))
* openapi documentation ([786d731](https://github.com/lumen-oss/luxpkgs/commit/786d73173a02a526df90c0d85e88b1195a49d5b7))
* overhaul Create API Key endpoint view ([bf3dab1](https://github.com/lumen-oss/luxpkgs/commit/bf3dab1806a231273d502e46f785ac7c4de50703))
* overhaul settings page ([8ed869a](https://github.com/lumen-oss/luxpkgs/commit/8ed869af671927c3fc10e30b7d07fb4bf8cc0990))
* package page ([ac37046](https://github.com/lumen-oss/luxpkgs/commit/ac37046fa02443cf2e1acbf3be978f19e60d3377))
* production deployment setup ([b4ab8f8](https://github.com/lumen-oss/luxpkgs/commit/b4ab8f8213919fd3aea5be9a0ffedee942273c46))
* revamp API keys page ([d0f8cdc](https://github.com/lumen-oss/luxpkgs/commit/d0f8cdc9c408522f707e27060013af4287e9a525))
* revamp landing page ([73a8b9a](https://github.com/lumen-oss/luxpkgs/commit/73a8b9a7cea05c6ddce71e9fb9f2168ab031bf3a))
* revamp sizing on frontend ([2abffd6](https://github.com/lumen-oss/luxpkgs/commit/2abffd6e6011adc71c82738c267a69f207b39449))
* revamp theme switcher ([6a7df27](https://github.com/lumen-oss/luxpkgs/commit/6a7df277096ec6fcbe3c5c70c3e99bb26696ea64))
* search page and general package list ([7f18a2f](https://github.com/lumen-oss/luxpkgs/commit/7f18a2f5e258016672f3497dfa51a7fe5eeb8bb5))
* verify user email on signup ([45a2ad9](https://github.com/lumen-oss/luxpkgs/commit/45a2ad91a57332fc96a4024d130673cc5d877c1a))


### Bug Fixes

* disallow deletion of releases ([ac3a40a](https://github.com/lumen-oss/luxpkgs/commit/ac3a40a50b1a26c1e85c59fe4cc5a053dcca6caf))
* make dark theme the default ([afb3d64](https://github.com/lumen-oss/luxpkgs/commit/afb3d64eca77e4173afc53dc1b316d43ec131fb5))
* oauth failure on some user accounts ([f0cbdf5](https://github.com/lumen-oss/luxpkgs/commit/f0cbdf5777acd37192a2b9012a99a21a11c4120d))
* remove unnecessary `br` tag in landing, use `reliable` instead of `scalable` in the typed.js array ([29e16c2](https://github.com/lumen-oss/luxpkgs/commit/29e16c27217c14cd7d048a5771b9852b76eb903b))
* spacing issues on main page ([489e279](https://github.com/lumen-oss/luxpkgs/commit/489e27915325c84ac419ae8d7943c1d95714feba))


### Miscellaneous Chores

* change release version to `0.1.0` ([37311e8](https://github.com/lumen-oss/luxpkgs/commit/37311e85c813d5371bbcac98c7fbd69091b8852e))


### Code Refactoring

* move `luxpkgs-rockspec-verifier` into the repository ([3eff2a4](https://github.com/lumen-oss/luxpkgs/commit/3eff2a434280fb979fcbe1c7090ab5e4ded633ef))

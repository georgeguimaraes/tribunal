# Changelog

## [1.1.1](https://github.com/georgeguimaraes/tribunal/compare/v1.1.0...v1.1.1) (2026-01-21)


### Miscellaneous

* **deps-dev:** bump ex_doc from 0.39.3 to 0.40.0 ([#7](https://github.com/georgeguimaraes/tribunal/issues/7)) ([e32af86](https://github.com/georgeguimaraes/tribunal/commit/e32af86c620da726dd137b70e4afc1b64ee2a223))
* **deps:** bump actions/cache from 3 to 5 ([#5](https://github.com/georgeguimaraes/tribunal/issues/5)) ([bb8612d](https://github.com/georgeguimaraes/tribunal/commit/bb8612df06d7ab8fe680fff53166c656dde66990))
* **deps:** bump actions/checkout from 4 to 6 ([#6](https://github.com/georgeguimaraes/tribunal/issues/6)) ([488c229](https://github.com/georgeguimaraes/tribunal/commit/488c2292c0a9a18a8c31b7669d79e6b9e5da85b9))
* **deps:** bump amannn/action-semantic-pull-request from 5 to 6 ([#4](https://github.com/georgeguimaraes/tribunal/issues/4)) ([f153bc5](https://github.com/georgeguimaraes/tribunal/commit/f153bc55b85f7eaca3d832f5df1584d637b03f15))
* sync release-please config with arcana ([3b6c6a6](https://github.com/georgeguimaraes/tribunal/commit/3b6c6a6618df9d0b4b6616e229e1300cd17af5fa))


### Code Refactoring

* **ci:** use release-please for GitHub releases ([7e6dd6e](https://github.com/georgeguimaraes/tribunal/commit/7e6dd6e535f1cd79aa691197cc9ccda7d277a8d2))
* **ci:** use shared workflows from georgeguimaraes/workflows ([b7fe021](https://github.com/georgeguimaraes/tribunal/commit/b7fe0212dc24b4b5d2cad36644c65f4f3ebec2d0))


### Continuous Integration

* add dependabot for mix and github-actions ([adbd1fb](https://github.com/georgeguimaraes/tribunal/commit/adbd1fbede74ba16cf7e8076795388542a1f0d05))

## [1.1.0](https://github.com/georgeguimaraes/tribunal/compare/v1.0.0...v1.1.0) (2026-01-15)


### Features

* add --concurrency flag for parallel test case execution ([87b6e16](https://github.com/georgeguimaraes/tribunal/commit/87b6e164c1195fa9439327e7c643b4611eb5a23d))
* add --threshold and --strict flags to mix tribunal.eval ([ff4f8b2](https://github.com/georgeguimaraes/tribunal/commit/ff4f8b2938d6e58d0088904822cba8f6073a0c3c))
* add LLM-based PII detection alongside regex ([0be8e9e](https://github.com/georgeguimaraes/tribunal/commit/0be8e9e44d9cfcb5e8f5fd0946312154478aa5bc))
* add text and html reporters ([36a4459](https://github.com/georgeguimaraes/tribunal/commit/36a4459dbcf74b2112403a52acd420d39607e85e))
* add verbose mode for score reasoning output ([768de5b](https://github.com/georgeguimaraes/tribunal/commit/768de5b7077332389830969fc2bc0be26cd81a7a))
* expand LLM PII detection with comprehensive categories ([59f7e58](https://github.com/georgeguimaraes/tribunal/commit/59f7e58cda06fbbf35ec4aced6ceef78cb76ae72))
* extract built-in judges to modules with Judge behaviour ([42de6bd](https://github.com/georgeguimaraes/tribunal/commit/42de6bde43313738b8752b11ed04c97a839c8286))
* improve judge prompts with research-backed evaluation criteria ([20b724a](https://github.com/georgeguimaraes/tribunal/commit/20b724a31062d1fb3e432566612e54830df31172))
* improve toxicity detection prompt with research-backed categories ([ed3ec38](https://github.com/georgeguimaraes/tribunal/commit/ed3ec3870cbc31182ff9dc1cef442b347baed186))
* migrate refusal from deterministic to LLM-based judge ([e7738a4](https://github.com/georgeguimaraes/tribunal/commit/e7738a45d7da378122b56f370308e7d5d4c7f47a))
* move PII and toxicity detection to LLM-based evaluation ([3c1e37a](https://github.com/georgeguimaraes/tribunal/commit/3c1e37a8e2fe49e2832faac4a830d25fca67d470))
* pass full TestCase to provider function ([18acf9a](https://github.com/georgeguimaraes/tribunal/commit/18acf9a43b249a87ad82630392488a52d1077701))
* show threshold status in console reporter output ([f6835d2](https://github.com/georgeguimaraes/tribunal/commit/f6835d2057b6a78202edc825024cbd89e58c0de7))


### Bug Fixes

* align release workflows with arcana patterns ([2cfdfa3](https://github.com/georgeguimaraes/tribunal/commit/2cfdfa3e3ac0954f6bc59c004131038934734e52))
* CI cache key and test parallelism issues ([11f12be](https://github.com/georgeguimaraes/tribunal/commit/11f12becb82909351c2e281d957baa71ac472d5c))
* default to exit 0, require explicit --threshold or --strict to fail ([8c50bb9](https://github.com/georgeguimaraes/tribunal/commit/8c50bb993a862f311c718e711d4778fd33641c3e))
* improve CI cache key to prevent stale build artifacts ([90894a4](https://github.com/georgeguimaraes/tribunal/commit/90894a489f5cc64978ed0a0938aacf97ce7fb6fa))
* mark release PR as tagged after publishing ([e26a1fa](https://github.com/georgeguimaraes/tribunal/commit/e26a1fa631be7a20a515dd721f9252bbc273a1bb))
* remove _build cache to prevent stale artifacts ([8b81113](https://github.com/georgeguimaraes/tribunal/commit/8b81113a486955d5bb28bafe7cf455b718651f68))
* use String.to_atom for YAML assertion parsing ([5e8e55e](https://github.com/georgeguimaraes/tribunal/commit/5e8e55ede2c77c8b3fdafef7810215d33c5aa43e))


### Documentation

* add application config section to llm-as-judge guide ([126b550](https://github.com/georgeguimaraes/tribunal/commit/126b5502a142f063d8fe01d4b8ec281017cc8510))
* add GitHub Actions integration guide ([7ba92cf](https://github.com/georgeguimaraes/tribunal/commit/7ba92cf72930ae22d35615003aca7779597c3ea9))
* Add link to tribunal-juror showcase app ([23b79db](https://github.com/georgeguimaraes/tribunal/commit/23b79db86acaa5bf270439a8f382d6dd4cdf593b))
* add scales emoji to README title ([18e956f](https://github.com/georgeguimaraes/tribunal/commit/18e956fbf20cce1e0a8ca39892bc6bcbf544256f))
* document ExUnit vs Mix Task evaluation modes ([b7b987d](https://github.com/georgeguimaraes/tribunal/commit/b7b987d63a55eaa49d3238bad85ca8f416684da9))
* rename Assertion Mode to Test Mode ([24bcb25](https://github.com/georgeguimaraes/tribunal/commit/24bcb25b82c1124bb45aba848c313f2498a5fba1))
* restore README intro with evaluating and testing ([c5e7989](https://github.com/georgeguimaraes/tribunal/commit/c5e7989144ee7c811db1f6ccae44b2d0bae1ed2e))
* update README intro ([88aa47f](https://github.com/georgeguimaraes/tribunal/commit/88aa47f6713193309741acacc373102cca1ee371))


### Code Refactoring

* fix credo strict warnings ([1fb32f6](https://github.com/georgeguimaraes/tribunal/commit/1fb32f63fc53800a4d7573976559b89a9ae31f78))
* fix credo warnings and add credo dependency ([10f9201](https://github.com/georgeguimaraes/tribunal/commit/10f9201f4690ba7078fceb334a45b646b8845704))
* rename llm_client to llm, judge_model to llm config key ([9c24c8c](https://github.com/georgeguimaraes/tribunal/commit/9c24c8c05dde249ee161f2e9d831b715e327a190))
* use Logger instead of IO.puts for verbose output ([6dfd0d6](https://github.com/georgeguimaraes/tribunal/commit/6dfd0d629f4983df67345e42f8d4428a10df3dba))


### Tests

* add LLM integration tests for all judge assertions ([dfe9ca2](https://github.com/georgeguimaraes/tribunal/commit/dfe9ca2d7d98538081bef79cb97495c9568db092))

## 1.0.0 (2026-01-12)


### Features

* add LLM-based safety metrics ([c5b2591](https://github.com/georgeguimaraes/tribunal/commit/c5b25917af9a07a504b14e9b43a1cd046791728c))
* add safety and utility assertions ([a5946f6](https://github.com/georgeguimaraes/tribunal/commit/a5946f66476f6db6c519acb353ba730b771fdc70))
* implement Tier 1 and Tier 2 LLM evaluation framework ([bfb458d](https://github.com/georgeguimaraes/tribunal/commit/bfb458db79dae9aa914163ca558eca2a9a42d969))
* rename Judicium to Tribunal with documentation ([9cead1d](https://github.com/georgeguimaraes/tribunal/commit/9cead1d86767625fe4a8337000acf531c881a46c))

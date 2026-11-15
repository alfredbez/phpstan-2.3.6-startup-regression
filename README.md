# PHPStan 2.3.6: slower start when only a small part of a big project is analysed

Since PHPStan 2.3.6, every run takes several seconds longer in a project with
many files in its Composer `autoload` section, when only a small part of the
project is in `paths`. The extra time is spent before "Result cache restored",
so it is also there when the result cache is warm and nothing changed.

We run PHPStan on a large monorepo in many small jobs, each with its own
`paths`. With 2.3.6 every job got about 4 to 5 seconds slower, with the same
amount for small and large jobs.

## The project

`generate.php` writes a project with two parts:

- `src/Lib`: many small classes (40,000 by default). They are in the Composer
  autoload section (`App\` => `src/`), but they are not analysed.
- `src/Small`: 10 classes. Only these are analysed (`paths` in `phpstan.neon`).

There are no extensions, no baseline, no bootstrap files.

## Run it

```sh
php generate.php 40000
composer install
bin/compare.sh 10 2.3.5 2.3.6   # needs hyperfine
bin/bisect.sh 2.3.5 2.3.6       # needs hyperfine and jq, clones phpstan-src
```

The GitHub Actions workflow does the same. See the job logs and the job
summaries of the latest run in the Actions tab.

## Results

See the latest run in the Actions tab for the numbers on a GitHub runner. On a
laptop (PHP 8.5, 40,000 classes, 10 warm runs) we got:

| | 2.3.5 | 2.3.6 |
| --- | ---: | ---: |
| Warm, nothing changed | 1.5 s | 3.5 s |
| Cold, tmpDir deleted | 2.6 s | 5.8 s |

The difference grows with the number and the size of the files in the
autoload section that are not analysed.

## What we think happens

`git bisect` points to phpstan-src commit
[603c305a6](https://github.com/phpstan/phpstan-src/commit/603c305a6e1a1dacb692a39dc626d4282b54946c)
"Track the files of the project's Composer autoload entries like scanned
files".

Since this commit, `ResultCacheManager::getScannedFiles()` also collects all
files of the project's Composer autoload entries, and it hashes each one that
is not analysed with `hash_file('sha256', ...)`. This happens on every run.
Analysed files can reuse their hash from the result cache when the file stat
did not change, but these files are hashed again every time.

When we add timing around the parts of `getScannedFiles()` in our monorepo
(tens of thousands of PHP files in the autoload section), finding the files
takes about 0.1 s, and hashing them takes about 5 s.

A job that analyses the whole project does not see much difference, because
almost all files are analysed files there and are left out before hashing.

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

From [this run](https://github.com/alfredbez/phpstan-2.3.6-startup-regression/actions/runs/43768242498)
on a GitHub runner (PHP 8.4, mean of 10 runs, only the 10 files in
`src/Small` are analysed):

| Autoloaded classes | Case | 2.3.5 | 2.3.6 |
| ---: | --- | ---: | ---: |
| 10,000 | Warm, nothing changed | 0.98 s | 1.11 s |
| 10,000 | Cold, tmpDir deleted | 1.81 s | 1.94 s |
| 10,000 | Warm, OS file cache dropped | 1.17 s | 2.02 s |
| 40,000 | Warm, nothing changed | 0.97 s | 1.41 s |
| 40,000 | Cold, tmpDir deleted | 1.77 s | 2.25 s |
| 40,000 | Warm, OS file cache dropped | 1.12 s | 3.22 s |

"OS file cache dropped" is like a CI job on a new machine: the result cache is
restored, but the project files were not read yet. 2.3.5 does not read the
files in `src/Lib` at all, 2.3.6 reads all of them.

The bisect job finds the same commit every time: from source, the parent
commit takes 0.69 s and the commit 1.10 s (fastest of 5 warm runs, 40,000
classes).

On a laptop with slower file access the difference is larger (40,000 classes,
warm: 1.5 s with 2.3.5, 3.5 s with 2.3.6).

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

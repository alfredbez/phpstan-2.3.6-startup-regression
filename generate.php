<?php

declare(strict_types=1);

// Writes a project with many autoloaded classes in src/Lib and a small part
// in src/Small. Only src/Small is analysed (see phpstan.neon), but src/ as a
// whole is in the Composer autoload section.
//
// Usage: php generate.php [number of classes] [methods per class]

$count = (int) ($argv[1] ?? 40000);
$methods = (int) ($argv[2] ?? 8);
$perDir = 200;

for ($i = 0; $i < $count; $i++) {
    $module = sprintf('Module%03d', intdiv($i, $perDir));
    $dir = __DIR__ . '/src/Lib/' . $module;
    if (!is_dir($dir)) {
        mkdir($dir, 0777, true);
    }

    $class = sprintf('Service%05d', $i);
    $body = '';
    for ($m = 0; $m < $methods; $m++) {
        $body .= <<<PHP

    /**
     * Adds {$m} to the value and the given number.
     */
    public function add{$m}(int \$other): int
    {
        if (\$other < 0) {
            return \$this->value - \$other + {$m};
        }

        return \$this->value + \$other + {$m};
    }

PHP;
    }

    file_put_contents($dir . '/' . $class . '.php', <<<PHP
<?php

declare(strict_types=1);

namespace App\\Lib\\{$module};

final class {$class}
{
    public function __construct(private int \$value = {$i})
    {
    }
{$body}}

PHP);
}

$small = __DIR__ . '/src/Small';
if (!is_dir($small)) {
    mkdir($small, 0777, true);
}

for ($i = 0; $i < 10; $i++) {
    $used = $i * 7;
    $module = sprintf('Module%03d', intdiv($used, $perDir));
    $class = sprintf('Service%05d', $used);
    file_put_contents($small . "/Small{$i}.php", <<<PHP
<?php

declare(strict_types=1);

namespace App\\Small;

use App\\Lib\\{$module}\\{$class};

final class Small{$i}
{
    public function run({$class} \$service): int
    {
        return \$service->add0({$i});
    }
}

PHP);
}

echo "Wrote {$count} classes to src/Lib and 10 classes to src/Small\n";

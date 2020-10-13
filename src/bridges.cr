require "./bridges/*"

require "yaml"
require "crystar"
require "lz4"
require "benchmark"

# TODO: Write documentation for `Bridges`
module Bridges
  include Crystar

  class Error < Exception
  end

  VERSION = "0.1.0"
end

pkg = Bridges::Package.new

Benchmark.ips do |bm|
  bm.report("Bridges - create") do
    pkg.create "test_package", "test_out"
  end

  bm.report("Tar - create") do
    # `tar -cf test_out/test_0.2.0.tar.lz4 test_package`
    `tar cf - test_package | lz4 -BX -3 > test_out/test_0.2.0.tar.lz4`
  end
end

Benchmark.ips do |bm|
  bm.report("Bridges - metadata") do
    pkg.decompress "test_out"
  end

  bm.report("Tar - metadata") do
    `tar -C test_out/ -I lz4 -xf test_out/test_0.2.0.tar.lz4 test_package/package.yml`
  end
end

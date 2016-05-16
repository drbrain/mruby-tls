MRuby::Gem::Specification.new('mruby-tls') do |spec|
  spec.license = 'Apache-2'
  spec.author  = 'Hendrik Beskow'
  spec.summary = 'mruby bindings to libtls'

  spec.add_dependency 'mruby-errno'

  def spec.bundle_libressl
    require 'rake/clean'

    return if @libressl_bundled

    @libressl_bundled = true

    libressl_version = '2.3.4'

    linker.libraries.delete 'tls'

    libressl_dir      = "#{build_dir}/libressl-#{libressl_version}"
    libressl_inc      = "#{libressl_dir}/include"
    libressl_makefile = "#{libressl_dir}/Makefile"

    if ENV['OS'] == 'Windows_NT'
      libtls_lib = libfile "#{libressl_dir}/libtls_s"
    else
      libtls_lib = libfile "#{libressl_dir}/tls/.libs/libtls"
    end

    header = "#{libressl_inc}/tls.h"

    libressl_objs_glob = "#{libressl_dir}/**/*.o"
    libmruby_a = libfile "#{build.build_dir}/lib/libmruby"

    CLEAN << libressl_dir

    directory build_dir do
      mkdir_p build_dir
    end

    directory libressl_dir => build_dir do
      sh 'tar', 'xzf', "#{dir}/vendor/libressl-#{libressl_version}.tar.gz",
                '-C', build_dir
    end

    file header => libressl_dir

    file libressl_makefile => libressl_dir do
      cd libressl_dir do
        if ENV['OS'] != 'Windows_NT'
          if build.kind_of? MRuby::CrossBuild
            host = ['--host', build.name]
          end

          sh './autogen.sh' if File.exists? 'autogen.sh'
          sh './configure', '--disable-shared', '--enable-static', *host

          # use config.log to determine the library we need here
          have_clock_gettime = false
          clock_gettime_library = nil

          File.foreach 'config.log' do |line|
            have_clock_gettime = true if /^ac_cv_func_clock_gettime=yes/ =~ line

            if /^ac_cv_search_clock_gettime=(.*)/ =~ line then
              next if $1 == 'no'
              next if $1 == "'none required'"

              /^-l/ =~ $1

              clock_gettime_library = $'
            end
          end

          $stderr.puts "Adding -l#{clock_gettime_library}" if Rake.application.options.trace

          linker.libraries << clock_gettime_library if
            have_clock_gettime and clock_gettime_library
        else
          sh 'cmd /c "copy /Y win32 > NUL"'
          cp 'Makefile.mingw', 'Makefile'
        end
      end
    end

    # this is a task not a file so the libmruby_a dependencies are updated
    # correctly every time
    task libtls_lib => [header, libressl_makefile] do
      cd libressl_dir do
        sh 'make'
      end

      file libmruby_a => Rake::FileList[libressl_objs_glob]
    end

    file "#{dir}/src/mrb_tls.c" => libtls_lib

    cc.include_paths << libressl_inc
  end

  if build.cc.respond_to? :search_header_path and build.cc.search_header_path 'tls.h'
    spec.linker.libraries << 'tls'
  else
    spec.bundle_libressl
  end
end

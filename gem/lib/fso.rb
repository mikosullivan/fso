require 'fileutils'
require 'pathname'
require 'forwardable'
require 'lx'
require 'ezcapture'
require 'ezcapture/verbose'


#===============================================================================
# FSO
#
class FSO
	attr_reader :path_abs
	attr_reader :hold
	
	# if paths should be given as relative or absolute
	@path_str = :relative
	
	# paths
	@paths = {}
	@paths['tmp'] = '/tmp'
	@paths['file'] = '/usr/bin/file'
	@paths['zip'] = '/usr/bin/zip'
	@paths['unzip'] = '/usr/bin/unzip'
	@paths['diff'] = '/usr/bin/diff'
	@paths['shuf'] = '/usr/bin/shuf'
	@paths['md5sum'] = '/usr/bin/md5sum'
	@paths['grep'] = '/usr/bin/grep'
	@paths['attr'] = '/usr/bin/attr'
	@paths['touch'] = '/usr/bin/touch'
	
	# recognized mime types
	@mime_types = {}
	@mime_types['application/zip'] = {'file'=>'fso/file-types/zip.rb', 'class'=>'FSO::File::Zip'}
	@mime_types['application/json'] = {'file'=>'fso/file-types/json.rb', 'class'=>'FSO::File::JSON'}
	@mime_types['text/xml'] = {'file'=>'fso/file-types/xml.rb', 'class'=>'FSO::File::XML'}
	@mime_types['image/svg+xml'] = @mime_types['text/xml']
	@mime_types['text/html'] = {'file'=>'fso/file-types/html.rb', 'class'=>'FSO::File::HTML'}
	
	
	#--------------------------------------------------------------------------
	# initialize
	#
	def initialize(p_path)
		@path_abs = ::File.absolute_path( FSO.to_path(p_path) )
		@hold = nil
		@attr = nil
	end
	#
	# initialize
	#--------------------------------------------------------------------------
	
	
	#--------------------------------------------------------------------------
	# path_rel
	#
	# This method returns the path of the file relative to the current working
	# directory, not relative to the directory when the object was created.
	# 
	# KLUDGE: I jump through a few hoops here for the simple reason that if a
	# file is in the current directory, I want its relative path to start with
	# "./", not just the file name.
	def path_rel(base=nil)
		abs = Pathname.new(@path_abs)
		rv = abs.relative_path_from(::Dir.pwd).to_s
		
		# special case: if the file is in the current directory, prepend "./" to
		# the path
		if ::File.dirname(@path_abs) == ::Dir.pwd
			rv = "./#{rv}"
		end
		
		# return
		return rv
	end
	#
	# path_rel
	#--------------------------------------------------------------------------

	
	#--------------------------------------------------------------------------
	# path
	#
	def path(*opts)
		if FSO.path_str == :relative
			return path_rel(*opts)
		else
			return @path_abs
		end
	end
	#
	# path
	#--------------------------------------------------------------------------
	
	
	#--------------------------------------------------------------------------
	# size
	#
	def size
		return ::File.size(path)
	end
	#
	# size
	#--------------------------------------------------------------------------
	
	
	# inode
	def inode
		return ::File.stat(path).ino
	end
	
	# misc
	def misc(create=true)
		instance_variable_defined?('@misc') or @misc = {}
		return @misc
	end
	
	# found
	def found()
		instance_variable_defined?('@found') or @found = []
		return @found
	end
	
	# to_s
	def to_s
		return path
	end
	
	# exist?
	def exist?(rel_path=nil)
		if rel_path
			return relative(rel_path).exist?
		else
			return ::File.exist?(@path_abs)
		end
	end
	
	# name
	def name
		return ::File.basename(@path_abs)
	end
	
	# attr
	def attr
		@attr ||= FSO::Attr.new(self)
		return @attr
	end
	
	# []
	def [](*opts)
		if opts.empty?
			return attr
		else
			raise 'not yet implemented using FSO as hash'
		end
	end
	
	# file?
	def file?
		return ::File.exist?(@path_abs) && ::File.file?(@path_abs)
	end
	
	# dir?
	def dir?
		return ::File.exist?(@path_abs) && ::File.directory?(@path_abs)
	end
	
	# executable?
	# Raises nil if the file doesn't exist. Returns false for  directories,
	# although they are technically executables.
	def executable?
		exist? or return nil
		return ::File.executable?(@path_abs) && (not ::File.directory?(@path_abs))
	end
	
	# delete
	# Deletes the file. No error is raised if the file did not exists to begin
	# with.
	def delete(opts={})
		frozen? and raise 'cannot-delete-with-frozen-file-object'
		FileUtils.rm_rf @path_abs
		return true
	end
	
	# extension
	def extension
		# get extension without dot
		ext = ::File.extname(path)
		ext = ext.sub(/\A\./mu, '')
		
		# if nm is empty, no extension, else return ext
		return ext.empty? ? nil : ext
	end
	
	# dir
	# returns the parent directory
	def dir
		# special case: root directory
		if path_abs == '/'
			return nil
		else
			return FSO.existing( ::File.dirname(path_abs) )
		end
	end

	# ==
	# returns true if the other FSO object has the same path
	def ==(other)
		unless other.is_a?(FSO) || other.is_a?(String)
			raise 'invalid-param-for-=='
		end
		
		return path_abs == FSO.to_fso(other).path_abs
	end
	
	# !=
	# returns false if the other FSO object has the same path
	def !=(other)
		unless other.is_a?(FSO) || other.is_a?(String)
			raise 'invalid-param-for-!='
		end
		
		return !self.==(other)
	end
	
	# symlink
	def symlink(tgt)
		tgt.is_a?(FSO) and tgt = tgt.path
		::File.symlink path, tgt
		return FSO.existing(tgt)
	end
	
	# symlink?
	# returns the target of a symbolic link or nil, or nil if the file is not a
	# symbolic link
	def symlink?
		if ::File.symlink?(path)
			target = ::File.readlink(path)
			return FSO.existing(target) || FSO.new(target)
		else
			return nil
		end
	end
	
	# target
	# does the same thing as symlink?
	alias_method :target, :symlink?
	
	# working_symlink?
	def working_symlink?
		return ::File.exist?(target.path)
	end
	
	# broken_symlink?
	def broken_symlink?
		return !working_symlink?
	end

	# mime
	def mime
		return FSO::Mime.new(self)
	end
	
	# text?
	def text?
		return mime_type.start_with?('text/')
	end
	
	# relative
	def relative(rel_path, clss=FSO)
		rel = Pathname.new(rel_path)
		
		if dir?
			return clss.new(rel.expand_path(path_abs))
		else
			return clss.new(rel.expand_path(dir.path_abs))
		end
	end
	
	# existing_all
	def existing_all(*maybes)
		rv = []
		pattern = maybes.include?(:glob)
		maybes = maybes.reject {|e| e.is_a?(Symbol)}
		
		if pattern
			maybes.each do |maybe|
				rv += glob(maybe)
			end
		else
			maybes.each do |maybe|
				if found = existing(maybe)
					rv.push found
				end
			end
		end
		
		return rv
	end
	
	# move
	def move(tgt)
		tgt = FSO.to_fso(tgt)
		
		if tgt.dir?
			new_path = tgt.path_abs + '/' + name
		else
			new_path = tgt.path_abs
		end
		
		FileUtils.move path, tgt.path_abs
		@path_abs = new_path
	end

	#--------------------------------------------------------------------------
	# within?
	#
	def within?(other)
		return FSO.ensure_fso(other).contains?(self)
	end
	#
	# within?
	#--------------------------------------------------------------------------
	
	
	#--------------------------------------------------------------------------
	# touch
	#
	def touch()
		cap = EzCapture.new(FSO.paths['touch'], path)
		cap.raise_on_failure 'file-touch-error'
	end
	#
	# touch
	#--------------------------------------------------------------------------
	
	
	# private
	private
	
	# expand_path_to
	def expand_path_to(other_path)
		other = Pathname.new(other_path)
		
		if dir?
			return other.expand_path(path_abs)
		else
			return other.expand_path(dir.path_abs)
		end
	end
end
#
# FSO
#===============================================================================


#===============================================================================
# FSO class methods
#
class << FSO
	attr_reader :paths
	attr_reader :mime_types
	attr_accessor :path_str
	
	# delegate to pwd
	extend Forwardable
	delegate %w(existing existing_all mkdir file) => :pwd
	
	# ensure_fso
	def ensure_fso(obj)
		if obj.is_a?(self)
			return obj
		elsif File.exist?(obj)
			return self.existing(obj)
		else
			return self.new(obj)
		end
	end
	
	# return object for /tmp or whatever is the tmp directory
	def tmp(*opts, &block)
		return get_dir(@paths['tmp'], *opts, &block)
	end
	
	# root
	def root(*opts, &block)
		return get_dir('/', *opts, &block)
	end
	
	
	#--------------------------------------------------------------------------
	# touch
	#
	def touch(rel_path)
		f = FSO.existing(rel_path) || file(rel_path)
		f.touch
		return f
	end
	#
	# touch
	#--------------------------------------------------------------------------
	
	
	# pwd
	def pwd(*opts, &block)
		return get_dir(FSO::Dir.new('./'), *opts, &block)
	end
	
	# initiator
	def initiator
		init_path = caller_locations[-1].absolute_path
		return FSO.existing(init_path)
	end
	
	# home
	def home(*opts, &block)
		ENV['HOME'] or raise 'home-directory-not-defined'
		return get_dir(ENV['HOME'], *opts, &block)
	end
	
	# this_file
	def this_file(idx=0, &block)
		return FSO::File.new(caller_locations[idx].path)
	end
	
	# this_dir
	def this_dir(*opts, &block)
		return get_dir(this_file(1).dir, *opts, &block)
	end
	
	# to_fso
	def to_fso(file)
		return file.is_a?(FSO) ? file : FSO.new(file)
	end
	
	# to_path
	def to_path(file)
		return file.is_a?(FSO) ? file.path : file
	end
	
	# classes for different file types
	def classes
		return {
			'file'=>FSO::File,
			'dir'=>FSO::Dir
		};
	end
	
	# exist?
	def exist?(in_path)
		return self.new(in_path).exist?
	end
	
	# tmp_tmp
	def tmp_tmp(*opts, &block)
		tmp.tmp do |nested|
			return FSO.get_dir(nested, *opts, &block)
		end
	end
	
	# chdir
	def chdir(tgt, &block)
		tgt = FSO.existing(tgt)
		
		if block_given?
			tgt.chdir() do
				yield tgt
			end
		else
			tgt.chdir
			return tgt
		end
	end
	
	# by_symbol
	def by_symbol(symbol)
		return send(symbol.to_s)
	end
	
	# get_dir
	def get_dir(tgt, *opts, &block)
		tgt = FSO::Dir.ensure_fso(tgt)
		
		if block_given?
			if opts.include?(:chdir)
				tgt.chdir do
					yield tgt
				end
			else
				yield tgt
			end
		end
		
		return tgt
	end
end
#
# FSO class methods
#===============================================================================


#===============================================================================
# FSO::File
#
class FSO::File < FSO
	# delegate to dir
	extend Forwardable
	delegate %w(chdir existing) => :dir
	
	
	#---------------------------------------------------------------------------
	# read, write
	#
	def read()
		return ::File.read(@path_abs)
	end
	
	def write(str)
		frozen? and raise 'cannot-write-with-frozen-file-object'
		return ::File.write(@path_abs, str)
	end
	#
	# read, write
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# execute
	#
	def execute(*opts)
		return EzCapture.new(path, *opts)
	end
	#
	# execute
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# md5sum
	#
	def md5sum()
		cap = EzCapture.new(FSO.paths['md5sum'], path)
		return cap.stdout.split(/\s+/mu)[0]
	end
	#
	# md5sum
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# sample
	#
	def sample(n=1)
		cmd = [FSO.paths['shuf'], '-n', n, path]
		cap = EzCapture.new(*cmd)
		return cap.stdout.lines.map {|l| l.chomp}
	end
	#
	# sample
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# zip
	#
	def zip(target)
		require 'fso/file-types/zip'
		
		# determine target path
		target.is_a?(FSO) or target = FSO.new(target)
		
		# go to dir for this file
		chdir() do
			# run zip command
			cmd = FSO.paths['zip'], target.path, path
			cap = ::EzCapture.new(*cmd)
			cap.raise_on_failure 'file-zip-error'
			return FSO::File::Zip.new(target)
		end
	end
	#
	# zip
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# ancestors
	#
	def ancestors(opts={})
		return [dir] + dir.ancestors(opts)
	end
	#
	# ancestors
	#---------------------------------------------------------------------------


	#---------------------------------------------------------------------------
	# to_h
	#
	def to_h(*opts)
		rv = {}
		
		# misc
		if instance_variable_defined?('@misc')
			rv['misc'] = @misc
		end
		
		# properties of the file
		if tgt = symlink?
			rv['symlink'] = tgt.path
		else
			opts.include?(:size) and rv['size'] = size
			opts.include?(:mime) and rv['mime_type'] = mime_type
			opts.include?(:mime_type) and rv['mime_type'] = mime_type
			opts.include?(:md5sum) and rv['md5sum'] = md5sum
		end
		
		# return
		return rv
	end
	#
	# to_h
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# json
	#
	def json
		require 'json'
		
		# initialize @hold if necessary
		if not @hold
			# if file exists, slurp in json
			if exist?
				@hold = JSON.parse(read())
			
			# if file doesn't exist, initialize to hash
			else
				@hold = {}
			end
			
			# link back to file object
			def @hold.file=(f)
				@file = f
			end
			
			@hold.file = self
			
			# save method
			def @hold.save
				return @file.write(self.to_json)
			end
		end
		
		# return
		return @hold
	end
	#
	# json
	#---------------------------------------------------------------------------
end
#
# FSO::File
#===============================================================================


#===============================================================================
# FSO::Dir
#
class FSO::Dir < FSO
	# alias parent to dir
	alias_method :parent, :dir
	
	#---------------------------------------------------------------------------
	# mkdir
	#
	def mkdir(new_dir, *opts, &block)
		# TTM.hrm new_dir
		new_dir = expand_path_to(new_dir)
		new_dir = FSO::Dir.ensure_fso(new_dir)

		if new_dir.exist?()
			if opts.include?(:ensure)
				if not new_dir.dir?
					raise 'file-exists-but-not-directory: ' + new_dir.path_abs
				end
			else
				raise 'directory-already-exists: ' + new_dir.path_abs
			end
		else
			new_dir.ensure
		end
		
		return FSO.get_dir(new_dir, *opts, &block)
	end
	#
	# mkdir
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# traverse
	#
	def traverse(chdir=false, &block)
		children.each do |child|
			yield child
			
			if child.dir?
				child.traverse chdir, &block
			end
		end
	end
	#
	# traverse
	#---------------------------------------------------------------------------
	

	#---------------------------------------------------------------------------
	# to_h
	#
	def to_h(*opts)
		rv = {'children'=>{}}
		kids = rv['children']
		
		# misc
		if instance_variable_defined?('@misc')
			rv['misc'] = @misc
		end

		# children
		children().each do |child|
			if tgt = child.target
				kids[child.name] = tgt.name
			else
				kids[child.name] = child.to_h(*opts)
			end
		end
		
		# return
		return rv
	end
	#
	# to_h
	#---------------------------------------------------------------------------

	
	#---------------------------------------------------------------------------
	# glob
	# KLUDGE: This method changes into the directory to run the glob.
	#
	def glob(pattern)
		rv = []
		
		chdir do
			::Dir.glob(pattern).each do |g|
				file = FSO.existing(g)
				rv.push file
			end
		end
		
		return rv
	end
	#
	# glob
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# existing: FSO::Dir#existing
	#
	def existing(other_path)
		# early exit
		other_path.nil? and return nil
		
		# get absolute path to file
		if other_path.is_a?(FSO)
			other_path = other_path.path_abs
		else
			other_path = ::File.expand_path(other_path, path_abs)
		end
		
		# check if path exists
		if not ::File.exist?(other_path)
			# special case: broken symlink
			if ::File.symlink?(other_path)
				return ::FSO.new(other_path)
			end
			
			# no file exists, so return nil
			return nil
		end
		
		# if dir
		if ::File.directory?(other_path)
			return FSO::Dir.new(other_path)
			
		# if file, return an instantiation specific to that file mime-type, or
		# return an instantiation of FSO::File
		elsif ::File.file?(other_path)
			return FSO::File.new(other_path)
		end
	end
	
	# []
	# does the same thing as existing
	alias_method :[], :existing
	
	#
	# existing
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# search
	#
	def search(*queries)
		return FSO::Dir::Search.new(self, queries).found
	end
	#
	# search
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# children
	#
	def children(opts={})
		rv = FSO::Dir::Children.new()
		
		# go into this directory
		chdir do
			# get list of entries
			entries = ::Dir.entries('./')
			
			# filter out . and ..
			entries = entries.reject do |entry|
				entry.match(/\A\.+\z/mu)
			end
			
			# loop through entries
			entries.each do |entry_path|
				rv.push FSO.existing(entry_path)
			end
		end
		
		return rv
	end
	#
	# children
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# ensure
	#
	def ensure
		if not exist?
			# ::Dir.mkdir @path_abs
			::FileUtils.mkdir_p @path_abs
		end
	end
	#
	# ensure
	#---------------------------------------------------------------------------
		
	
	#---------------------------------------------------------------------------
	# file
	#
	def file(file_name, clss=FSO::File)
		full = "#{path_abs}/#{file_name}"
		return existing(full) || clss.new(full)
	end
	#
	# file
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# files
	#
	def files
		rv = FSO::Dir::Children.new()
		
		children.each do |child|
			if child.file?
				rv.push child
			end
		end
		
		return rv
	end
	#
	# files
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# dirs
	#
	def dirs
		rv = FSO::Dir::Children.new()
		
		children.each do |child|
			if child.dir?
				rv.push child
			end
		end
		
		return rv
	end
	#
	# dirs
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# symlinks
	#
	def symlinks
		rv = FSO::Dir::Children.new()
		
		children.each do |child|
			if child.symlink?
				rv.push child
			end
		end
		
		return rv
	end
	#
	# symlinks
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# executables
	#
	def executables
		rv = FSO::Dir::Children.new()
		
		children.each do |child|
			if child.executable?
				rv.push child
			end
		end
		
		return rv
	end
	#
	# executables
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# chdir
	#
	def chdir
		if block_given?
			start = FSO.pwd
			
			begin
				::Dir.chdir(path_abs)
				yield self
			ensure
				::Dir.chdir(start.path_abs)
			end
		else
			::Dir.chdir(path)
			return self
		end
	end
	#
	# chdir
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# tmp
	#
	def tmp(opts={})
		opts.is_a?(Hash) or opts={'chdir'=>opts}
		opts['root'] = path_abs
		
		::Dir.lx.tmp(opts) do |dir_path|
			path = FSO.existing(dir_path)
			
			if opts['chdir']
				path.chdir do
					yield path
				end
			else
				yield path
			end
		end
	end
	#
	# tmp
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# zip
	#
	def zip(target)
		require 'fso/file-types/zip'
		
		# determine target path
		target.is_a?(FSO) or target = FSO.new(target)
		
		# go to dir for this file
		chdir() do
			# run zip command
			cmd = FSO.paths['zip'], '-r', target.path_abs, path
			cap = ::EzCapture.new(*cmd)
			cap.raise_on_failure 'directory-zip-error'
			return FSO::File::Zip.new(target)
		end
	end
	#
	# zip
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# tmp_path
	#
	def tmp_path(*opts)
		::File.lx.tmp_path(*opts) do |path|
			yield FSO.new(path)
		end
	end
	#
	# tmp_path
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# root?
	#
	def root?
		return @path_abs == '/'
	end
	#
	# root?
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# home?
	#
	def home?
		return @path_abs == FSO.home.path_abs
	end
	#
	# home?
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# ===
	#
	def ===(other)
		cmd = FSO.paths['diff'], '--recursive', '--brief', path, other.path
		cap = EzCapture.new(*cmd)
		return cap.success?
	end
	#
	# ===
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# ancestor
	#
	def ancestor(*opts)
		return ancestors(*opts)[-1]
	end
	#
	# ancestor
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# ancestors
	#
	def ancestors(opts={})
		tgt_dir = opts.lx[:tgt]
		org_tgt_dir = tgt_dir
		
		# check for file
		if tgt_file = opts.lx[:tgt_file]
			if exist?(tgt_file)
				return []
			end
		end
		
		# if tgt is a symbol, get the FSO object that associated with that symbol
		if tgt_dir.is_a?(Symbol)
			tgt_dir = FSO.by_symbol(tgt_dir)
		end
		
		# at this point, target must be either nil, a string or an FSO
		unless tgt_dir.nil? or tgt_dir.is_a?(String) or tgt_dir.is_a?(FSO)
			raise 'tgt-not-fso-or-string: ' + tgt_dir.class.to_s
		end
		
		# If this is the root directory, we've either finished finding
		# ancestors, or we've failed to find the target ancestor.
		# 
		# NOTE: This code gets a little spaghettish. Some tightening up of the
		# code is needed.
		if root?
			if tgt_dir
				if tgt_dir.is_a?(FSO::Dir)
					error = !tgt_dir.root?
				else
					error = true
				end
				
				if org_tgt_dir.is_a?(Symbol)
					detail = ':' + org_tgt_dir.to_s
				else
					detail = tgt_dir.to_s
				end
				
				error and raise 'did-not-find-target-ancestor: ' + detail
			end
			
			return []
		else
			if tgt_dir
				# if tgt is a string
				if tgt_dir.is_a?(String)
					if tgt_dir == name
						return []
					end
				
				# else if this directory is the target
				else
					if self == tgt_dir
						return []
					end
				end
			end
			
			return [dir] + dir.ancestors(opts)
		end
	end
	#
	# ancestors
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# contains?
	#
	def contains?(other)
		other = FSO.ensure_fso(other)
		return other.path_abs.to_s.start_with?(path_abs.to_s)
	end
	#
	# contains?
	#---------------------------------------------------------------------------
end
#
# FSO::Dir
#===============================================================================


#===============================================================================
# FSO::Dir::Search
#
class FSO::Dir::Search
	attr_reader :dir
	attr_reader :queries
	attr_reader :found
	
	# initialize
	def initialize(p_dir, p_queries)
		@dir = p_dir
		@queries = p_queries
		@found = nil
		list_files()
	end
	
	# list_files
	def list_files
		paths = {}
		
		# build command
		cmd = []
		cmd.push FSO.paths['grep']
		cmd.push '-r'
		cmd += @queries.map {|q| "-e #{::Regexp.escape(q)}" }
		cmd.push @dir.path
		
		# execute
		cap = EzCapture.new(*cmd)
		
		# loop through lines
		cap.stdout.lines.each do |line|
			path, txt = line.split(':', 2)
			
			if all_queries?(txt)
				paths[path] ||= FSO.existing(path)
				paths[path].found.push txt
			end
		end
		
		# return
		@found = paths.values
	end
	
	# all_queries?
	def all_queries?(txt)
		@queries.each do |q|
			if not txt.include?(q)
				return false
			end
		end
		
		return true
	end
end
#
# FSO::Dir::Search
#===============================================================================


#===============================================================================
# FSO::Dir::Children
#
class FSO::Dir::Children < Array
	#---------------------------------------------------------------------------
	# by_name
	#
	def by_name
		rv = {}
		
		each do |kid|
			rv[kid.name] = kid
		end
		
		return rv
	end
	#
	# by_name
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# names
	#
	def names
		return by_name.keys
	end
	#
	# names
	#---------------------------------------------------------------------------
end
#
# FSO::Dir::Children
#===============================================================================


#===============================================================================
# FSO::Attr
#
class FSO::Attr
	attr_accessor :key
	
	#---------------------------------------------------------------------------
	# initialize
	#
	def initialize(file)
		@file = file
		@key = 'fso'
	end
	#
	# initialize
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# []=
	#
	def []=(key, val)
		# TTM.hrm
		
		# command
		cmd = [FSO.paths['attr'], '-s', key, '-V', val, @file.path_abs]
		cap = EzCapture.new(*cmd)
		cap.raise_on_error 'unable-to-set-attribute'
	end
	#
	# []=
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# []
	#
	def [](key)
		# TTM.hrm
		
		# if key not set, return nil
		if not keys.include?(key)
			return nil
		end
		
		# command
		cmd = [FSO.paths['attr'], '-q', '-g', key, @file.path_abs]
		cap = EzCapture.new(*cmd)
		cap.raise_on_error 'unable-to-get-attribute'
		return cap.stdout
	end
	#
	# []
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# keys
	#
	def keys
		# TTM.hrm
		
		cmd = [FSO.paths['attr'], '-q', '-l', @file.path_abs]
		cap = EzCapture.new(*cmd)
		cap.raise_on_error 'unable-to-get-keys'
		
		return cap.stdout.split("\n")
	end
	#
	# keys
	#---------------------------------------------------------------------------
	
	
	#---------------------------------------------------------------------------
	# delete
	#
	def delete(key)
		# TTM.hrm
		
		if keys.include?(key)
			rv = self[key]
			cmd = [FSO.paths['attr'], '-r', key, @file.path_abs]
			cap = EzCapture.new(*cmd)
			cap.raise_on_error 'unable-to-delete-attribute'
			return rv	
		else
			return nil
		end
		
	end
	#
	# delete
	#---------------------------------------------------------------------------
end
#
# FSO::Attr
#===============================================================================


# load some additional files
require 'fso/file-types/zip.rb'
require 'fso/mime.rb'
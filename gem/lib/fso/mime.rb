#==============================================================================
# FSO::Mime
#
class FSO::Mime
	# initialize
	def initialize(p_file)
		@file = p_file
	end
	
	# type
	def type
		cmd = FSO.paths['file'], '--mime-type', '--brief', @file.path.to_s
		cap = ::EzCapture.new(*cmd)
		cap.raise_on_failure 'error-getting-mime-type'
		return cap.stdout.lx.collapse
	end
	
end
#
# FSO::Mime
#==============================================================================
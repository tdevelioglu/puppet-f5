module Puppet::Util::Ldiff
  def self.diff(data_old, data_new, format=:unified, context_lines=3)
    unless Puppet.features.diff?
      Puppet.warning "Cannot provide diff without the diff/lcs Ruby library"
      return ""
    end

    data_old = data_old.split($/).map { |e| e.chomp }
    data_new = data_new.split($/).map { |e| e.chomp }
 
    output = ""
 
    diffs = ::Diff::LCS.diff(data_old, data_new)
    return output if diffs.empty?
 
    oldhunk = hunk = nil
    file_length_difference = 0

    diffs.each do |piece|
      begin
        hunk = ::Diff::LCS::Hunk.new(data_old, data_new, piece,
                         context_lines, file_length_difference)
        file_length_difference = hunk.file_length_difference
        next unless oldhunk
        next if (context_lines > 0) and hunk.merge(oldhunk)
        output << oldhunk.diff(format) << "\n"
      ensure
        oldhunk = hunk
      end
    end
 
    output << oldhunk.diff(format) << "\n"
  end
end

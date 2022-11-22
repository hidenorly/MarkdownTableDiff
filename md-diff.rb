#!/usr/bin/env ruby

# Copyright 2022 hidenory
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fileutils'
require 'optparse'
require 'shellwords'
require_relative 'FileUtil'
require_relative 'ExecUtil'
require_relative 'Reporter'

class MarkdownParser
	def self.getMarkdownTableFromFile(path, dataOnly=true, multipleTables=false)
		results = {}

		body = FileUtil.readFileAsArray(path)

		result = []
		key = nil
		body.each do |aLine|
			if !aLine.strip.start_with?("#") then
				result << parseTable(aLine)
			else
				results[key] = result if key && !result.empty?
				result = []
				key = aLine.slice(1,aLine.length).strip
			end
		end
		results[key ? key : "none"] = result if !result.empty?
		result = []

		if dataOnly then
			results2={}
			results.each do |aKey, aResult|
				results2[aKey] = cleanupWithoutHeader(aResult)
			end
			results = results2
		end

		return multipleTables ? results : results.values.first
	end

	def self.parseTable(aLine, enableMultiLine=true)
		result = []

		if aLine.include?("|") then
			aLine.strip!
			aLine=aLine[1..aLine.length] if aLine.start_with?("|")
			data = aLine.split("|")
			data.each do |aData|
				aData.strip!
				aData = aData[0..aData.length-2] if aData.end_with?(" |")
				if enableMultiLine && aData.include?(" <br> ") then
					_data = aData.split(" <br> ")
					aData = []
					_data.each do |_aData|
						_aData.strip!
						aData << _aData
					end
				end
				result << aData
			end
		end

		return result
	end

	def self.getTableColsFromArray(body)
		result = []

		for i in 0..body.length do
			aLine = body[i]
			if i>0 && aLine.to_s.include?(":---") or aLine.to_s.include?(":---:") or aLine.to_s.include?("---:") then
				tmp = body[i-1].split("|")
				tmp.each do |aRow|
					aRow.strip!
					result << aRow if !aRow.empty?
				end
				break
			end
		end

		return result
	end

	def self.getTableColsFromFile(mdTablePath)
		body = FileUtil.readFileAsArray(mdTablePath)
		return getTableColsFromArray(body)
	end

	def self.cleanupWithoutHeader(data)
		result = data

		found=nil
		for i in 1..data.length do
			aLine = data[i].to_s
			if aLine.include?(":---") or aLine.include?(":---:") or aLine.include?("---:") then
				found = i
				break
			end
		end

		if found!=nil then
			result = result.drop(found+1)
		end

		return result
	end

	def self.getEnsuredCols(paths)
		cols=[]
		paths.each do |aPath|
			aCols= getTableColsFromFile(aPath)
			if aCols then
				cols = cols | aCols
			end
		end
		return cols
	end
end

class DiffTableUtil
	def self.getDiffTable(body, dataOnly=true)
		added=[]
		removed=[]

		body.each do |aLine|
			storeTo = aLine.start_with?("+") ? added : aLine.start_with?("-") ? removed : [] # non-diffed lines are ignored
			storeTo << MarkdownParser.parseTable(aLine[1..aLine.length])
		end

		added = MarkdownParser.cleanupWithoutHeader(added) if dataOnly
		removed = MarkdownParser.cleanupWithoutHeader(removed) if dataOnly

		return added, removed
	end

	def self.convertArrayToHashWithCols(data, cols, targetKey)
		result = {}

		aTargetCol = cols.find_index(targetKey)
		aTargetCol = aTargetCol ? aTargetCol : 0

		data.each do |aLine|
			i=0
			aData = {}
			aLine.each do |aRow|
				aData[ cols[i] ] = aRow
				i=i+1
			end
			result[ aData[targetKey] ] = aData # 0 is packageName, assume
		end

		return result
	end

	def self.isIdenticalWithoutIgnoreCols(added, removed, ignoreCols)
		result = true

		added.each do |key, anAdded|
			if !ignoreCols.include?(key) then
				result = removed.has_key?(key) && (anAdded.to_s.strip == removed[key].to_s.strip)
			end
			break if result == false
		end

		return result
	end

	def self._getDelta(added, removed, ignoreCols)
		result = nil

		if !isIdenticalWithoutIgnoreCols(added, removed, ignoreCols) then
			result = {}

			# add +/-
			added.each do |key, anAdded|
				if ignoreCols.include?(key) then
					result[key] = anAdded
				else
					aResult = []
					anAdded = [ anAdded ] if !anAdded.kind_of?(Array)
					aRemoved = []
					if removed.has_key?(key) then
						if removed[key].kind_of?(Array) then
							aRemoved = removed[key]
						else
							aRemoved = [ removed[key] ]
						end
					end
					adds = (anAdded - aRemoved)
					removes = (aRemoved - anAdded)
					if !adds.empty? || !removes.empty? then
						removes.each do |aData|
							aData = aData.to_s.strip
							aResult << "-#{aData}" if !aData.empty?
						end
						adds.each do |aData|
							aData = aData.to_s.strip
							aResult << "+#{aData}" if !aData.empty?
						end
					else
						aResult = anAdded
					end
					aResult.uniq!
					aResult = aResult[0].to_s if aResult.length == 1
					result[key] = aResult
				end
			end
		end

		return result
	end

	def self.addPrefixEachData(aLine, ignoreCols, prefix = "+")
		result = {}

		if aLine && aLine.kind_of?(Hash) then
			aLine.each do |key, aData|
				if ignoreCols.include?(key) then
					result[key] = aData
				else
					aResult = []
					# multi line cases
					aData = [ aData ] if !aData.kind_of?(Array)
					aData.each do |aColumnData|
						aColumnData = aColumnData.to_s.strip
						aResult << "#{prefix}#{aColumnData}" if !aColumnData.empty?
					end
					aResult.uniq!
					aResult = aResult[0].to_s if aResult.length == 1
					result[key] = aResult
				end
			end
		end

		return result
	end


	def self.addPrefixEachDatas(tables, ignoreCols, prefix = "+")
		results = []

		if tables then
			if !tables.kind_of?(Array) then
				results = addPrefixEachData(tables, ignoreCols, prefix)
			else
				tables.each do |aLine|
					result = addPrefixEachData(aLine, ignoreCols, prefix)
					results << result if result && !result.empty?
				end
			end
		end

		return results
	end

	def self._convArrayToHash(cols)
		result = {}

		cols.each do |aCol|
			result[ aCol ] = aCol
		end

		return cols
	end

	def self.getAnalyzedDiffedData(added, removed, cols, diffIgnoreCols, enablePrefix=false)
		diffed = []
		pureAdded = []
		pureRemoved = []

		added.each do |anAdded, aData|
			if removed.has_key?(anAdded) then
				tmp = _getDelta(aData, removed[anAdded], diffIgnoreCols)
				diffed << tmp if tmp && tmp.length
			else
				aData = enablePrefix ? addPrefixEachData(aData, [], "+") : aData
				pureAdded << aData if aData && aData.length
			end
		end

		removed.each do |aRemoved, aData|
			if !added.has_key?(aRemoved) then
				aData = enablePrefix ? addPrefixEachData(aData, [], "-") : aData
				pureRemoved << aData if aData && aData.length
			end
		end

		return pureAdded, pureRemoved, diffed
	end

	def self.getPureDiff(oldFile, newFile)
		exec_cmd = "diff -u -r -N #{Shellwords.escape(oldFile)} #{Shellwords.escape(newFile)}"
		exec_cmd = "#{exec_cmd} | grep '^[+|-]|'"
		return ExecUtil.getExecResultEachLine(exec_cmd)
	end

	def self._getLabel(path)
		path = FileUtil.getFilenameFromPath(path)
		pos = path.rindex(".md")
		path = path.slice(0, pos) if pos
		pos = path.rindex("-")
		path = path.slice(pos+1, path.length) if pos

		return path
	end

	def self.createDiffReport(paths, outputReportPath = nil, reportSections = ["added", "removed", "diffed"], diffIgnoreCols = [], enableSectionWithFilename = false)
		if paths.length == 2 then
			# read diff report
			added, removed = getDiffTable( getPureDiff(paths[0], paths[1]) )

			# convert the diffed report with cols
			cols = MarkdownParser.getEnsuredCols(paths) # get OR-ed cols from multiple markdown files
			keyColumn = cols[0]
			added = convertArrayToHashWithCols(added, cols, keyColumn)
			removed = convertArrayToHashWithCols(removed, cols, keyColumn)

			# get +/- added diffed tables
			diffIgnoreCols = [ keyColumn ] if diffIgnoreCols.empty?
			pureAdded, pureRemoved, diffed = DiffTableUtil.getAnalyzedDiffedData(added, removed, cols, diffIgnoreCols)

			# report
			reportPath = outputReportPath ? outputReportPath : nil # "Diff-#{_getLabel(paths[0])}-#{_getLabel(paths[1])}.md"
			reporter = MarkdownReporter.new( reportPath )

			if !pureAdded.empty? && (!reportSections || reportSections.include?("added")) then
				title = "added"
				title = "#{title} by #{paths[1]} from #{paths[0]}" if enableSectionWithFilename
				reporter.titleOut(title)
				reporter.report(pureAdded)
				reporter.println()
			end

			if !pureRemoved.empty? && (!reportSections || reportSections.include?("removed")) then
				title = "removed"
				title = "#{title} by #{paths[1]} from #{paths[0]}" if enableSectionWithFilename
				reporter.titleOut(title)
				reporter.report(pureRemoved)
				reporter.println()
			end

			if !diffed.empty? && (!reportSections || reportSections.include?("diffed")) then
				title = "diffed"
				title = "#{title} between #{paths[0]} and #{paths[1]}" if enableSectionWithFilename
				reporter.titleOut(title)
				reporter.report(diffed)
				reporter.println()
			end

			reporter.close()
		end
	end

	def self.createDiffDiffReport(paths, outputReportPath = nil, diffIgnoreCols = [])
		if paths.length == 2 then
			# get cols
			cols = MarkdownParser.getEnsuredCols(paths)
			keyColumn = [ cols[0] ]

			# read data
			oldTables_ = MarkdownParser.getMarkdownTableFromFile(paths[0], true, true)
			newTables_ = MarkdownParser.getMarkdownTableFromFile(paths[1], true, true)

			oldTables = {}
			newTables = {}
			sections = []
			oldTables_.each do |aSection, aTable|
				oldTables[aSection] = DiffTableUtil.convertArrayToHashWithCols(aTable, cols, keyColumn)
				sections << aSection
			end
			newTables_.each do |aSection, aTable|
				newTables[aSection] = DiffTableUtil.convertArrayToHashWithCols(aTable, cols, keyColumn)
				sections << aSection
			end
			sections.uniq!

			diffIgnoreCols = [ cols[0] ] if diffIgnoreCols.empty?
			diffeds = {}

			sections.each do |aSection|
				aResult = nil
				if newTables.has_key?(aSection) && oldTables.has_key?(aSection) then
					pureAdded, pureRemoved, diffed = getAnalyzedDiffedData(newTables[aSection], oldTables[aSection], cols, diffIgnoreCols, true)
					pureAdded = pureAdded + diffed + pureRemoved
					aResult = pureAdded if !pureAdded.empty?

				elsif newTables.has_key?(aSection) && !oldTables.has_key?(aSection) then
					aResult = addPrefixEachDatas(newTables[aSection], [], "+")
				else
					aResult = addPrefixEachDatas(oldTables[aSection], [], "-")
				end
				diffeds[aSection] = aResult if aResult && !aResult.empty?
			end

			reporter = MarkdownReporter.new( outputReportPath )
			diffeds.each do |aSection, diffed|
				reporter.titleOut(aSection)
				reporter.report(diffed)
				reporter.println()
			end
			reporter.close()
		end
	end
end

options = {
	:enableDiffDiff => false,
	:enableSectionWithFilename => false,
	:outputReportSection => "added|removed|diffed",
	:ignoreCols => nil,
	:sortFiles => "*",
	:verbose => false
}

opt_parser = OptionParser.new do |opts|
	opts.banner = "Usage: old.md new.md (reportPath)"

	opts.on("-o", "--outputReportSection=", "Specify to markdown report output section for each project (#{options[:outputReportSection]})") do |outputReportSection|
		options[:outputReportSection] = outputReportSection
	end

	opts.on("-f", "--enableSectionWithFilename", "Enable filename to section (default:#{options[:enableSectionWithFilename]})") do
		options[:enableSectionWithFilename] = true
	end

	opts.on("-d", "--diffdiff", "Enable diff diff mode (default:#{options[:enableDiffDiff]})") do
		options[:enableDiffDiff] = true
	end

	opts.on("-s", "--sortFiles=", "Specify manual sort e.g. fileA.md,fileB.md,* *:remaining (default:#{options[:sortFiles]})") do |sortFiles|
		options[:sortFiles] = sortFiles
	end

	opts.on("-v", "--verbose", "Enable verbose status output (default:#{options[:verbose]})") do
		options[:verbose] = true
	end
end.parse!

options[:outputReportSection] = options[:outputReportSection].split("|")
options[:ignoreCols] = options[:ignoreCols].to_s.split("|")


reportPath = ARGV.length == 3 ? ARGV[2] : nil

if ARGV.length>=2 then
	srcFiles = []
	dstFiles = []

	if File.directory?( ARGV[0] ) && File.directory?( ARGV[1] ) then
		# same file name diff mode in the specified directories
		# parse sort order
		sortFiles = options[:sortFiles].split(",")
		orders = []
		specifiedKeys = []
		i = 0
		sortFiles.each do |aFile|
			aFile.strip!
			current = orders[i]
			orders[i] = [] if !current || !current.kind_of?(Array)
			if aFile!="*" then
				orders[i] << aFile
				specifiedKeys << aFile
			else
				i = i + 1 if !orders[i].empty?
				orders[i] = "*" # NOT ARRAY
				i = i + 1
			end
		end

		_srcFiles = FileUtil.getFilenameHashFromPaths( FileUtil.getRegExpFilteredFiles( ARGV[0] ) )
		_dstFiles = FileUtil.getFilenameHashFromPaths( FileUtil.getRegExpFilteredFiles( ARGV[1] ) )

		commonFiles = _srcFiles.keys & _dstFiles.keys
		_srcFiles = _srcFiles.slice(*commonFiles)
		_dstFiles = _dstFiles.slice(*commonFiles)
		_srcFiles = _srcFiles.sort.to_h
		_dstFiles = _dstFiles.sort.to_h

		# put files by sort order
		remainingFiles = commonFiles - specifiedKeys
		found = false
		orders.each do |anOrder|
			if anOrder.kind_of?(Array) && !anOrder.empty? then
				srcFiles = srcFiles + _srcFiles.slice( *anOrder ).values
				dstFiles = dstFiles + _dstFiles.slice( *anOrder ).values
			else
				if !found then
					srcFiles = srcFiles + _srcFiles.slice( *remainingFiles ).values
					dstFiles = dstFiles + _dstFiles.slice( *remainingFiles ).values
					found = true
				end
			end
		end
	elsif File.exist?( ARGV[0] ) && File.exist?( ARGV[1] ) then
		srcFiles = [ ARGV[0] ]
		dstFiles = [ ARGV[1] ]
	end

	puts "---source files----\n#{srcFiles.join("\n")}" if options[:verbose]
	puts "---destination files----\n#{dstFiles.join("\n")}" if options[:verbose]

	isSingleFileMode = srcFiles.length == 1
	FileUtil.ensureDirectory( reportPath ) if reportPath && !isSingleFileMode
	srcFiles.zip(dstFiles).each do |aSrc, aDst|
		# one file mode
		_reportPath = isSingleFileMode ? reportPath : reportPath ? "#{reportPath}/#{FileUtil.getFilenameFromPath(aSrc)}" : reportPath
		if options[:enableDiffDiff] then
			DiffTableUtil.createDiffDiffReport([aSrc, aDst], _reportPath, options[:ignoreCols])
		else
			DiffTableUtil.createDiffReport([aSrc, aDst], _reportPath, options[:outputReportSection], options[:ignoreCols], options[:enableSectionWithFilename])
		end
	end
end

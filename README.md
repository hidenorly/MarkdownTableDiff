# MarkdownTableDiff

```
% ruby md-diff.rb
Usage: old.md new.md (reportPath)
    -o, --outputReportSection=       Specify to markdown report output section for each project (added|removed|diffed)
    -f, --enableSectionWithFilename  Enable filename to section (default:false)
    -d, --diffdiff                   Enable diff diff mode (default:false)
    -i, --ignoreCols=                Specify cols if you want to ignore the diff. e.g. filename|line if multiply ignoring
    -s, --sortFiles=                 Specify manual sort e.g. fileA.md,fileB.md,* *:remaining (default:*)
    -c, --singleFileMode             Enable single file report mode (default:false)
    -n, --dontReportIfNoDiff         Don't report if no diff (default:false)
    -v, --verbose                    Enable verbose status output (default:false)
```


# diff on specified file A and file B

```
$ ruby md-diff.rb old.md new.md
```


# diff on same file name files in specified directories A and B

```
$ ruby md-diff.rb old new
```

If old and new are directory, then enumerate files and do diff regarding same files.
If reportPath is specified, create the directory and output the diff regarding same files.

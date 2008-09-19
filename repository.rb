class Repository
  extend ElMixin

  CODE_SAMPLES = %q<
    # Show options for the repository
    - Show options: Repository.menu
  >

  def self.svn_command command, dir=nil
    dir ||= View.dir
    #dir ||= "tr"
    switch_to_buffer generate_new_buffer("*repository command")
    elvar.default_directory = Bookmarks.expand(dir)
    shell current_buffer
    #cm_universal_diff_format
    self.styles
    self.local_keys
    #difflog_highlight
    insert command
    Shell.enter
  end

  def self.svn?
    File.exists?("#{View.dir}.svn")
  end

  def self.diff_dir

    # if .svn dir found
    if self.svn?
      self.svn_command("echo; svn status; svn diff -x -w")
    else
      options = Keys.prefix_u? ? "$tr" : View.dir
      self.svn_command("git status; git diff -w . ", options)
    end

  end


  # Requires that this line be set somewhere:
  #   Repository.url = "http://svn.foo.com/svn/repos/foo"
  #     - Note that the above path should be to the dir containing
  #       trunk/, tags/, and branches/
  def self.tag to, from=nil
    unless Repository.url
      puts "Error: Repository.url isn't set!"
      return
    end
    from ||= "trunk"
    command = "svn -m \"Tag: Create #{from} tag\" cp #{Repository.url}/#{from} #{Repository.url}/#{to}"
    Shell.run(command)
  end

  def self.url= url
    @@url = url
  end

  def self.url
    @@url
  end

  def self.menu project=nil
    # If no project, show all projects
    if project.nil?
      return Projects.listing.map{|k, v| "#{k} - #{v}/"}
    end

    # If project, show options

    puts %Q[
      + .add/
      + .commit "message"/
      + .commit "message", :diffs/
      + .push/
      + .status/
      + .status_tree/
      + .log/
      ].strip.gsub(/^      /, '')
  end

  def self.log dir, rev=nil, file=nil
    dir ||= Keys.prefix_u? ? Bookmarks['$tr'] : self.determine_dir

    if rev.nil?   # If no rev, list all revs
      txt = Shell.run "git log --pretty=oneline", :sync=>true, :dir=>dir
      # Ol << "txt: #{txt}"
      # return
      txt.gsub! ':', '-'
      txt.gsub! /(.+?) (.+)/, "\\2: \\1"
      txt.gsub! /^- /, ''
      return txt.split("\n")
    end

    if file.nil?   # If no file, show files for rev
      # Rev passed, so show all diffs
      txt = Shell.run "git show --pretty=oneline --name-status #{rev}", :sync=>true, :dir=>dir
      txt.sub! /^.+\n/, ''
      txt.gsub! /^([A-Z])\t/, "\\1: "
      txt.gsub! /^M: /, ''
      return txt.split("\n").sort
    end

    # File passed, show diff
    txt = Shell.run "git show --pretty=oneline #{rev} #{file}", :sync=>true, :dir=>dir
    txt.sub!(/.+?@@.+?\n/m, '')
    txt.gsub! /^/, '|'
    puts txt
    return
  end

  def self.diff_one_file
    if Keys.prefix_u?  # If C-u
      cm_compare_one_svn_file
      return
    end

    if self.svn?
      cm_subversion_command("echo; svn diff -x -w #{file_name_nondirectory(buffer_file_name)}")
    else
      Shell.run("git diff '#{View.file}'")
      #cm_subversion_command("echo; svn diff -x -w #{file_name_nondirectory(buffer_file_name)}")
      self.styles
      self.local_keys
    end
  end

  def self.local_keys
    Keys.CN(:cm_diff_map) do
      Line.to_right
      re_search_forward "^index:? "
      Line.to_left
      recenter 0
    end
    Keys.CP(:cm_diff_map) do
      Line.to_left
      re_search_backward "^index:? "
      recenter 0
    end

    Keys._M(:cm_diff_map) { Repository.jump_to_file }
  end

  def self.jump_to_file
    orig = View.cursor
    Search.backward "^@@"
    inbetween = View.txt orig, View.cursor
    inbetween.gsub!(/^-.+\n/, '')
    inbetween = inbetween.split(/\n/).size
    line = Line.value[/\+(\d+)/, 1]
    Search.backward "^\\+\\+\\+"
    file = Line.value[/^\+\+\+ (.+)/, 1]
    file.sub!(/\t.+/, '')  # svn
    file.sub!(/^[ab]\//, '')  # git
    goto_char orig
    View.open(file)
    View.to_line(line.to_i + (inbetween - 1))
    Color.colorize :o
  end

  def self.jump_to_file_in_tree dir
    orig = View.cursor
    Search.backward "^ +\|@@"
    inbetween = View.txt(orig, View.cursor)
    inbetween.gsub!(/^ +\|~.*\n/, '')
    inbetween = inbetween.count("\n")
    line = Line.value[/\+(\d+)/, 1]
    Search.backward "^ +- "
    file = Line.value[/^ +- (.+)/, 1]
    goto_char orig

    View.open("#{dir}/#{file}")
    View.to_line(line.to_i + (inbetween - 1))
    Color.colorize :o
  end

  def self.styles_define
    Styles.define :face_difflog_path_outline_rest,
      :fg => "000077",
      :bg => "7070bb",
      :font => "arial"

    # - foo (r): <here>
    Styles.define :diff_subhead,
      :bg => "333366", :fg => "88b", :size => "-3"

    #:box => nil
    #:height => "
  end

  def self.styles
    cm_universal_diff_format
    difflog_highlight
    Styles.apply "^diff.+\n", :diff_subhead
    Styles.apply "^Index:? .+\n", :diff_subhead
    Styles.apply "^===+\n", :diff_subhead
    Styles.apply "^--- .+\n", :diff_subhead
    Styles.apply "^\\+\\+\\+ .+\n", :notes_h1
    Styles.apply "^\\\\.+", :cm_lighter_bold
    Styles.apply "^\\*.+\n", :treels_f_blank
    Styles.apply "^@@.+\n", :diff_subhead

  end

  # Called by key shortcut
  # Runs in new buffer, under code tree method
  def self.determine_dir
    # Check whether git

    git_status = Shell.run "git status", :sync => true, :dir => View.dir
    if git_status =~ /^fatal: Not a git repository/
      return Bookmarks['$tr']
    end

    dir = Shell.run("git rev-parse --git-dir", :sync=>true,
      :dir=>View.dir
      ).sub(".git\n", '')

    dir.any? ? dir : View.dir
  end

  def self.open_list_repository
    # Figure out which dir
    dir = Keys.prefix_u? ? Bookmarks['$tr'] : self.determine_dir

    View.to_buffer "*repository status"
    View.clear
    View.dir = dir
    TreeLs.apply_styles
    use_local_map elvar.notes_mode_map

    tree = self.status_tree_internal dir
    View.insert "- Repository.status_tree/\n#{tree.gsub(/^/, '  ')}"

    View.to_top
    Move.to_junior
    TreeLs.search :recursive => true

  end

  # Called by code tree directly
  def self.status_tree
    puts CodeTree.tree_search + self.status_tree_internal(Bookmarks['$tr'])
  end

  def self.status_tree_internal dir

    if self.svn?
      status = Shell.run "svn st", :dir => dir, :sync => true
      # Remove question files
      status = status.split("\n")#.select{|l| l !~ /^\?/}
      status = status.each{|l| l.sub!(/^. +/, dir)}
      TreeLs.paths_to_tree(status)
    else   # git
      status = Shell.run "git status", :dir => dir, :sync => true

      # Grab out modified:...
      found = status.scan(/^#\s+modified: +(.+)/)
      result = []
      found.each do |m|
        result << "#{dir}#{m[0]}"
      end
      TreeLs.paths_to_tree(result)
    end
  end

  def self.clean! txt
    txt.gsub!(/^index .+\n/, '')
    txt.gsub!(/^--- .+\n/, '')
    txt.gsub!(/^\+\+\+ .+\n/, '')
  end

  def self.extract_dir project
    project.sub(/.+? - /, '').sub(/\/$/, '')
  end

  def self.diff project, file=nil, line=nil

    dir = self.extract_dir project

    if file.nil?   # If no file passed, do whole diff

      txt = Shell.run "git status", :dir=>dir, :sync=>true
      files = txt.scan(/\t(.+)/).map{|i| i.first}
      new_files = files.select{|f| f =~ /^new file: +/}.map{|f| "new: " + f[/: +(.+)/, 1]}

      txt = Shell.run('git diff -U2', :sync => true, :dir => dir)
      self.clean! txt
      txt.gsub!(/^-/, '~')
      txt.gsub!(/^/, '  |')
      txt.gsub!(/^  \|diff --git .+ b\//, '- ')
      return new_files.map{|f| "- #{f}\n"}.join('') + txt
    end

    if line.nil?   # If no line passed, re-do diff for 1 file
      txt = Shell.run("git diff -U2 #{file}", :sync => true, :dir => dir)
      self.clean! txt
      txt.gsub!(/^diff .+\n/, '')
      txt.gsub!(/^-/, '~')
      txt.gsub!(/^/, '|')
      return puts(txt)
    end

    self.jump_to_file_in_tree dir   # If line passed, jump to it

    nil   # Be sure to have no return value
  end

  def self.status project, file=nil
    dir = self.extract_dir project
    #dir ||= self.determine_dir

    # If no file, show status
    if file.nil?
      txt = Shell.run("git status", :sync => true, :dir => dir)
      txt.gsub!(/^#\t/, '- ')
      txt.gsub!(/^#\n/, '')
      txt.gsub!(/^#/, '|')
      return puts txt
    end

    View.open("#{dir}/#{file}")   # If file, open it

  end

  def self.add project, file=nil

    dir = self.extract_dir project
    children = CodeTree.children || []

    # If file passed, just open it
    if file
      View.open("#{dir}/#{file}")   # If file, open it
      return
    end

    if children.nonempty?   # If children, add them
      #dir ||= self.determine_dir
      children = children.map{|c| c.sub(/^ +[+-] /, '')}.join(" ")
      #puts "git add #{children}"
      txt = Shell.run("git add #{children}", :dir => dir)

      return
    end

    # If no children, show ones to be added
    txt = Shell.run("git ls-files --others", :dir => dir, :sync => true)
    txt.split("\n")

  end

  def self.commit *args

    # Parse args
    message = args.shift
    diffs = args.shift if args.first.is_a? Symbol   # Pull out :diffs if 2nd arg
    project, file, line = args

    dir = self.extract_dir project
    children = CodeTree.children || []

    if file.nil?   # If launchinng .commit directly (no file)
      if children.nonempty?   # Files are underneath (children)
        children = children.map{|c| c.sub(/^ +[+-] /, '')}.join(" ")
        command = "git commit -m \"#{message}\" #{children}"
        Shell.run(command, :dir=>dir)
        return
      else   # If no files underneath, show modified files
        if !diffs

          txt = Shell.run "git status", :dir=>dir, :sync=>true
          files = txt.scan(/\t(.+)/).map{|i| i.first}
          new_files = files.select{|f| f =~ /^new file: +/}.map{|f| "new: " + f[/: +(.+)/, 1]}
          modified = files.select{|f| f =~ /^modified: +/}.map{|f| f[/: +(.+)/, 1]}

          return new_files + modified
          #return Shell.run("git ls-files --modified", :dir=>dir, :sync=>true).split("\n")
        end
        # else, .diff will show the diffs
      end
    end

    # Else, delegate to diff
    self.diff project, file, line
  end

  def self.push project
    dir = self.extract_dir project
    Shell.run "git push origin master", :dir=>dir
    nil
  end

  def self.compare_with_repository
    bookmark = Keys.input(:timed => true, :prompt => "Git dif in which dir? (enter bookmark): ")
    CodeTree.display_menu("Repository.menu/\n  - project - $#{bookmark}/\n    - .commit \"message\", :diffs")
  end

end
Repository.styles_define

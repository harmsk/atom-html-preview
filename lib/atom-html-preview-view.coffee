fs                    = require 'fs'
{CompositeDisposable, Disposable} = require 'atom'
{$, $$$, ScrollView}  = require 'atom-space-pen-views'
path                  = require 'path'
os                    = require 'os'

scrollInjectScript = """
<script>
(function () {
  var scriptTag = document.scripts[document.scripts.length - 1];
  document.addEventListener('DOMContentLoaded',()=>{
    var elem = document.createElement("span")
    try {
      // Scroll to this current script tag
      elem.style.width = 100
      // Center the scrollY
      elem.style.height = "20vh"
      elem.style.marginTop = "-20vh"
      elem.style.marginLeft = -100
      elem.style.display = "block"
      var par = scriptTag.parentNode
      par.insertBefore(elem, scriptTag)
      elem.scrollIntoView()
    } catch (error) {}
    try { elem.remove() } catch (error) {}
    try { scriptTag.remove() } catch (error) {}
  }, false)
})();
</script>
"""

module.exports =
class AtomHtmlPreviewView extends ScrollView
  atom.deserializers.add(this)

  editorSub           : null
  onDidChangeTitle    : -> new Disposable()
  onDidChangeModified : -> new Disposable()

  webviewElementLoaded : false
  renderLater : true

  @deserialize: (state) ->
    new AtomHtmlPreviewView(state)

  @content: ->
    @div class: 'atom-html-preview native-key-bindings', tabindex: -1, =>
      style = 'z-index: 2; padding: 2em;'
      @div class: 'show-error', style: style
      @tag 'webview', src: path.resolve(__dirname, '../html/loading.html'), outlet: 'htmlview', disablewebsecurity:'on', allowfileaccessfromfiles:'on', allowPointerLock:'on'

  constructor: ({@editorId, filePath}) ->
    super

    if @editorId?
      @resolveEditor(@editorId)
      @tmpPath = @getPath() # after resolveEditor
    else
      if atom.workspace?
        @subscribeToFilePath(filePath)
      else
        # @subscribe atom.packages.once 'activated', =>
        atom.packages.onDidActivatePackage =>
          @subscribeToFilePath(filePath)

    # Disable pointer-events while resizing
    handles = $("atom-pane-resize-handle")
    handles.on 'mousedown', => @onStartedResize()

    @find('.show-error').hide()
    @webview = @htmlview[0]

    @webview.addEventListener 'dom-ready', =>
      @webviewElementLoaded = true
      if @renderLater
        @renderLater = false
        @renderHTMLCode()


  onStartedResize: ->
    @css 'pointer-events': 'none'
    document.addEventListener 'mouseup', @onStoppedResizing.bind this

  onStoppedResizing: ->
    @css 'pointer-events': 'all'
    document.removeEventListener 'mouseup', @onStoppedResizing

  serialize: ->
    deserializer : 'AtomHtmlPreviewView'
    filePath     : @getPath()
    editorId     : @editorId

  destroy: ->
    if @editorSub?
      @editorSub.dispose()

  subscribeToFilePath: (filePath) ->
    @trigger 'title-changed'
    @handleEvents()
    @renderHTML()

  resolveEditor: (editorId) ->
    resolve = =>
      @editor = @editorForId(editorId)

      if @editor?
        @trigger 'title-changed' if @editor?
        @handleEvents()
      else
        # The editor this preview was created for has been closed so close
        # this preview since a preview cannot be rendered without an editor
        atom.workspace?.paneForItem(this)?.destroyItem(this)

    if atom.workspace?
      resolve()
    else
      # @subscribe atom.packages.once 'activated', =>
      atom.packages.onDidActivatePackage =>
        resolve()
        @renderHTML()

  editorForId: (editorId) ->
    for editor in atom.workspace.getTextEditors()
      return editor if editor.id?.toString() is editorId.toString()
    null

  handleEvents: =>
    contextMenuClientX = 0
    contextMenuClientY = 0

    @on 'contextmenu', (event) ->
      contextMenuClientY = event.clientY
      contextMenuClientX = event.clientX

    atom.commands.add @element,
      'atom-html-preview:open-devtools': =>
        @webview.openDevTools()
      'atom-html-preview:inspect': =>
        @webview.inspectElement(contextMenuClientX, contextMenuClientY)
      'atom-html-preview:print': =>
        @webview.print()


    changeHandler = =>
      @renderHTML()
      pane = atom.workspace.paneForURI(@getURI())
      if pane? and pane isnt atom.workspace.getActivePane()
        pane.activateItem(this)

    @editorSub = new CompositeDisposable

    if @editor?
      if atom.config.get("atom-html-preview.triggerOnSave")
        @editorSub.add @editor.onDidSave changeHandler
      else
        @editorSub.add @editor.onDidStopChanging changeHandler
      @editorSub.add @editor.onDidChangePath => @trigger 'title-changed'

  renderHTML: ->
    if @editor?
      if not atom.config.get("atom-html-preview.triggerOnSave") && @editor.getPath()?
        @save(@renderHTMLCode)
      else
        @renderHTMLCode()

  save: (callback) ->
    # Temp file path
    outPath = path.resolve path.join(os.tmpdir(), @editor.getTitle() + ".html")
    out = ""
    fileEnding = @editor.getTitle().split(".").pop()

    if atom.config.get("atom-html-preview.enableMathJax")
      out += """
      <script type="text/x-mathjax-config">
      MathJax.Hub.Config({
      tex2jax: {inlineMath: [['\\\\f$','\\\\f$']]},
      menuSettings: {zoom: 'Click'}
      });
      </script>
      <script type="text/javascript"
      src="http://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML">
      </script>
      """

    if atom.config.get("atom-html-preview.preserveWhiteSpaces") and fileEnding in atom.config.get("atom-html-preview.fileEndings")
      # Enclose in <pre> statement to preserve whitespaces
      out += """
      <style type="text/css">
      body { white-space: pre; }
      </style>
      """
    else
      # Add base tag; allow relative links to work despite being loaded
      # as the src of an webview
      out += "<base href=\"" + @getPath() + "\">"

    # Scroll into view
    editorText = @editor.getText()
    firstSelection = this.editor.getSelections()[0]
    { row, column } = firstSelection.getBufferRange().start

    if atom.config.get("atom-html-preview.scrollToCursor")
      try
        offset = @_getOffset(editorText, row, column)

        tagRE = /<((\/[\$\w\-])|br|input|link)\/?>/.source
        lastTagRE= ///#{tagRE}(?![\s\S]*#{tagRE})///i
        findTagBefore = (beforeIndex) ->
          #sample = editorText.slice(startIndex, startIndex + 300)
          matchedClosingTag = editorText.slice(0, beforeIndex).match(lastTagRE)
          if matchedClosingTag
            return matchedClosingTag.index + matchedClosingTag[0].length
          else
            return -1

        tagIndex = findTagBefore(offset)
        if tagIndex > -1
          editorText = """
          #{editorText.slice(0, tagIndex)}
          #{scrollInjectScript}
          #{editorText.slice(tagIndex)}
          """

      catch error
        return -1

    out += editorText

    @tmpPath = outPath
    fs.writeFile outPath, out, =>
      try
        @renderHTMLCode()
      catch error
        @showError error

  renderHTMLCode: () ->
    @find('.show-error').hide()
    @htmlview.show()

    if @webviewElementLoaded
      @webview.loadURL("file://" + @tmpPath)

      atom.commands.dispatch 'atom-html-preview', 'html-changed'
    else
      @renderLater = true

  # Get the offset of a file at a specific Point in the file
  _getOffset: (text, row, column=0) ->
    line_re = /\n/g
    match_index = null
    while row--
      if match = line_re.exec(text)
        match_index = match.index
      else
        return -1
    offset = match_index + column
    return if offset < text.length then offset else -1


  getTitle: ->
    if @editor?
      "#{@editor.getTitle()} Preview"
    else
      "HTML Preview"

  getURI: ->
    "html-preview://editor/#{@editorId}"

  getPath: ->
    if @editor?
      @editor.getPath()

  showError: (result) ->
    failureMessage = result?.message

    @htmlview.hide()
    @find('.show-error')
    .html $$$ ->
      @h2 'Previewing HTML Failed'
      @h3 failureMessage if failureMessage?
    .show()

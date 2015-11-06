fs                    = require 'fs'
{CompositeDisposable, Disposable} = require 'atom'
{$, $$$, ScrollView}  = require 'atom-space-pen-views'
path                  = require 'path'
os                    = require 'os'

module.exports =
class AtomHtmlPreviewView extends ScrollView
  atom.deserializers.add(this)

  editorSub           : null
  onDidChangeTitle    : -> new Disposable()
  onDidChangeModified : -> new Disposable()

  @deserialize: (state) ->
    new AtomHtmlPreviewView(state)

  @content: ->
    @div class: 'atom-html-preview native-key-bindings', tabindex: -1

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

  serialize: ->
    deserializer : 'AtomHtmlPreviewView'
    filePath     : @getPath()
    editorId     : @editorId

  destroy: ->
    # @unsubscribe()
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
    @showLoading()
    if @editor?
      @renderHTMLCode()

  save: (callback) ->
    # Temp file path
    outPath = path.resolve os.tmpdir() + @editor.getTitle()
    # Add base tag; allow relative links to work despite being loaded
    # as the src of an iframe
    out = "<base href=\"" + @getPath() + "\">" + @editor.getText()
    @tmpPath = outPath
    fs.writeFile outPath, out, callback

  renderHTMLCode: (text) ->
    if not atom.config.get("atom-html-preview.triggerOnSave") and @editor.getPath()? then @save () =>
      iframe = document.createElement("iframe")
      # Fix from @kwaak (https://github.com/webBoxio/atom-html-preview/issues/1/#issuecomment-49639162)
      # Allows for the use of relative resources (scripts, styles)
      iframe.setAttribute("sandbox", "allow-scripts allow-same-origin")
      iframe.src = @tmpPath
      @html $ iframe
      # @trigger('atom-html-preview:html-changed')
      atom.commands.dispatch 'atom-html-preview', 'html-changed'

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

    @html $$$ ->
      @h2 'Previewing HTML Failed'
      @h3 failureMessage if failureMessage?

  showLoading: ->
    @html $$$ ->
      @div class: 'atom-html-spinner', 'Loading HTML Preview\u2026'

path = require 'path'
{$, $$$, ScrollView} = require 'atom'
_ = require 'underscore-plus'

module.exports =
class AtomHtmlPreviewView extends ScrollView
  atom.deserializers.add(this)

  @deserialize: (state) ->
    new AtomHtmlPreviewView(state)

  @content: ->
    @div class: 'atom-html-preview native-key-bindings', tabindex: -1

  constructor: ({@editorId, filePath}) ->
    super

    if @editorId?
      @resolveEditor(@editorId)
    else
      if atom.workspace?
        @subscribeToFilePath(filePath)
      else
        @subscribe atom.packages.once 'activated', =>
          @subscribeToFilePath(filePath)

  serialize: ->
    deserializer: 'AtomHtmlPreviewView'
    filePath: @getPath()
    editorId: @editorId

  destroy: ->
    @unsubscribe()

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
        @parents('.pane').view()?.destroyItem(this)

    if atom.workspace?
      resolve()
    else
      @subscribe atom.packages.once 'activated', =>
        resolve()
        @renderHTML()

  editorForId: (editorId) ->
    for editor in atom.workspace.getEditors()
      return editor if editor.id?.toString() is editorId.toString()
    null

  handleEvents: ->

    changeHandler = =>
      @renderHTML()
      pane = atom.workspace.paneForUri(@getUri())
      if pane? and pane isnt atom.workspace.getActivePane()
        pane.activateItem(this)

    if @editor?
      @subscribe(@editor.getBuffer(), 'contents-modified', changeHandler)
      @subscribe @editor, 'path-changed', => @trigger 'title-changed'

  renderHTML: ->
    @showLoading()
    if @editor?
      @renderHTMLCode(@editor.getText())

  renderHTMLCode: (text) ->
    text = """
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8">
        <title>HTML Preview</title>
        <style>
          body {
            font-family: "Helvetica Neue", Helvetica, sans-serif;
            font-size: 14px;
            line-height: 1.6;
            background-color: #fff;
            overflow: scroll;
            box-sizing: border-box;
          }
        </style>
      </head>
      <body>
        #{text}
      </body>
    </html>
    """
    iframe = document.createElement("iframe")
    iframe.src = "data:text/html;charset=utf-8,#{encodeURI(text)}"
    @html $ iframe
    @trigger('atom-html-preview:html-changed')

  getTitle: ->
    if @editor?
      "#{@editor.getTitle()} Preview"
    else
      "HTML Preview"

  getUri: ->
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

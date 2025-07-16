class MonacoEditor extends HTMLElement {
    // attributeChangedCallback will be called when the value of one of these attributes is changed in html
    static get observedAttributes() {
        return ["value-for", "language"]
    }

    editor = null
    _form = null

    constructor() {
        super()

        // keep reference to <form> for cleanup
        this._form = null
        this._handleFormData = this._handleFormData.bind(this)
    }

    attributeChangedCallback(name, oldValue, newValue) {
        if (this.editor) {
            if (name === "value-for") {
                this.editor.setValue(this.getElementById(newValue).value)
            }

            if (name === "language") {
                const currentModel = this.editor.getModel()
                if (currentModel) {
                    currentModel.dispose()
                }

                this.editor.setModel(
                    monaco.editor.createModel(this._getEditorValue(), newValue)
                )
            }
        }
    }

    connectedCallback() {
        this._form = this._findContainingForm()
        if (this._form) {
            this._form.addEventListener("formdata", this._handleFormData)
        }

        // editor
        const editor = document.createElement("div")
        editor.style.minHeight = "300px"
        editor.style.maxHeight = "100vh"
        editor.style.height = "100%"
        editor.style.width = "100%"
        editor.style.resize = "vertical"
        editor.style.overflow = "auto"

        this.appendChild(editor)
        var readonlyAttr = false
        if (this.getAttribute("readonly") == "true") {
            readonlyAttr = true
        } 

        var init = () => {
            require(["vs/editor/editor.main"], () => {
                // Editor
                this.editor = monaco.editor.create(editor, {
                    theme: "vs-dark",
                    model: monaco.editor.createModel(
                        this.getAttribute("value"),
                        this.getAttribute("language")
                    ),
                    wordWrap: "on",
                    readOnly: readonlyAttr,
                    automaticLayout: true,
                    minimap: {
                        enabled: false
                    },
                    scrollbar: {
                        vertical: "auto"
                    }
                })
                this.editor.onDidChangeModelContent(e => {
                    if (this.getAttribute("value-for") != null) {
                        document.getElementById(this.getAttribute("value-for")).value = this.editor.getModel().getValue()
                    }
                });
            })
            window.removeEventListener("load", init)
        }

        window.addEventListener("load", init)

        
    }

    disconnectedCallback() {
        if (this._form) {
            this._form.removeEventListener("formdata", this._handleFormData)
            this._form = null
        }
    }

    _getEditorValue() {
        if (this.editor) {
            return this.editor.getModel().getValue()
        }

        return null
    }

    _handleFormData(ev) {
        document.getElementById(this.getAttribute("value-for")).value = this._getEditorValue()
        // ev.formData.append(this.getAttribute("name"), this._getEditorValue())
    }

    _findContainingForm() {
        // can only be in a form in the same "scope", ShadowRoot or Document
        const root = this.getRootNode()
        if (root instanceof Document || root instanceof Element) {
            const forms = Array.from(root.querySelectorAll("form"))
            // we can only be in one <form>, so the first one to contain us is the correct one
            return forms.find(form => form.contains(this)) || null
        }

        return null
    }
}
customElements.define("monaco-editor", MonacoEditor)

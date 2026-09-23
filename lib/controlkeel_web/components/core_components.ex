defmodule ControlKeelWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  built on Tailwind CSS. Here are useful references:

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: ControlKeelWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-hook="FlashTimeout"
      data-flash-kind={@kind}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="fixed right-4 top-4 z-50"
      {@rest}
    >
      <div class={[
        "w-80 sm:w-96 max-w-[calc(100vw-2rem)] text-wrap rounded-xl border bg-card p-4 shadow-card",
        @kind == :info && "border-info/30",
        @kind == :error && "border-destructive/40 bg-destructive/10"
      ]}>
        <div class="flex items-start gap-2">
          <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0 mt-0.5" />
          <.icon
            :if={@kind == :error}
            name="hero-exclamation-circle"
            class="size-5 shrink-0 mt-0.5 text-destructive"
          />
          <div class="min-w-0 flex-1">
            <p :if={@title} class="font-semibold text-foreground">{@title}</p>
            <p class="text-foreground/80">{msg}</p>
          </div>
          <button
            type="button"
            class="group self-start cursor-pointer rounded focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            aria-label={gettext("close")}
          >
            <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with a selectable variant.

  Variants:

    * `default` - solid primary fill, the default accent
    * `secondary` - muted soft fill for less prominent actions
    * `outline` - bordered transparent for neutral actions
    * `destructive` - soft destructive fill for high-risk actions

  Any additional attributes (such as `id`, `name`, `value`, `disabled`,
  `phx-click`) are passed through to the button element.

  ## Examples

      <.button>Submit</.button>
      <.button variant="outline" phx-click="cancel">Cancel</.button>
      <.button variant="destructive" type="submit" name="decision" value="denied">Deny</.button>
  """
  attr :variant, :string,
    default: "default",
    values: ~w(default secondary outline destructive)

  attr :type, :string, default: "button", values: ~w(button submit reset)
  attr :class, :any, default: nil, doc: "additional classes appended to the base styling"

  attr :rest, :global,
    include: ~w(id disabled name value form autofocus formaction formnovalidate)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={[
        "inline-flex items-center justify-center gap-1.5 rounded-lg px-4 py-1.5 text-xs font-semibold transition cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary/50 disabled:pointer-events-none disabled:opacity-50",
        button_variant_class(@variant),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp button_variant_class("default"),
    do: "bg-primary text-primary-foreground hover:bg-primary/90"

  defp button_variant_class("secondary"),
    do: "bg-secondary/30 hover:bg-secondary/40 border border-border/40 text-muted-foreground"

  defp button_variant_class("outline"),
    do: "border border-border bg-transparent text-foreground hover:bg-muted"

  defp button_variant_class("destructive"),
    do: "bg-destructive/20 hover:bg-destructive/30 border border-destructive/40 text-destructive"

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[
            @class ||
              "w-full rounded-xl border border-input bg-background",
            @errors != [] && (@error_class || "select-error")
          ]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class ||
              "w-full rounded-xl border border-input bg-background",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class ||
              "w-full rounded-xl border border-input bg-background",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  @doc """
  Renders a labeled input with the alternate soft-surface styling.

  `input_component` exists because a legacy `input` component is already
  used throughout the repo. Changing `input` now would ripple across many
  call sites, so new form fields are written against `input_component`
  (or `<.textarea>` for multi-line input) instead. Usages migrate slowly,
  and once the legacy `input` is fully replaced, `input_component` will
  be renamed to `input`.

  Accepts a `Phoenix.HTML.FormField` for the bound field, an optional icon
  and hint.

  ## Examples

      <.input_component field={@form[:title]} type="text" label="Title" icon="hero-bars-3" />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, required: true
  attr :value, :any
  attr :type, :string, default: "text"
  attr :field, Phoenix.HTML.FormField
  attr :errors, :list, default: [], doc: "error messages rendered below the input"
  attr :hint, :string, default: nil
  attr :icon, :string, default: nil
  attr :class, :any, default: nil, doc: "additional classes appended to the default styling"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required size step)

  def input_component(assigns) do
    assigns = assign_component_field(assigns)

    ~H"""
    <div>
      <.component_field_header icon={@icon} label={@label} id={@id} />
      <input
        type={@type}
        id={@id}
        name={@name}
        value={Phoenix.HTML.Form.normalize_value(@type, @value)}
        aria-invalid={@errors != [] || nil}
        class={[input_component_field_class(), @class]}
        {@rest}
      />
      <.component_field_error :for={msg <- @errors} message={msg} />
      <.component_field_hint :if={@hint} hint={@hint} />
    </div>
    """
  end

  defp input_component_field_class(),
    do:
      "h-8 w-full min-w-0 rounded-lg border border-input bg-transparent px-2.5 py-1 text-base transition-colors outline-none placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 disabled:pointer-events-none disabled:cursor-not-allowed disabled:bg-input/50 disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-3 aria-invalid:ring-destructive/20 md:text-sm"

  @doc """
  Renders a labeled textarea with the soft-surface styling.

  Accepts a `Phoenix.HTML.FormField` for the bound field, an optional icon
  and hint.

  ## Examples

      <.textarea field={@form[:feedback_notes]} label="Feedback notes" placeholder="Add notes..." />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, required: true
  attr :value, :any
  attr :field, Phoenix.HTML.FormField
  attr :errors, :list, default: [], doc: "error messages rendered below the textarea"
  attr :hint, :string, default: nil
  attr :icon, :string, default: nil
  attr :class, :any, default: nil, doc: "additional classes appended to the default styling"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required size step)

  def textarea(assigns) do
    assigns = assign_component_field(assigns)

    ~H"""
    <div>
      <.component_field_header icon={@icon} label={@label} id={@id} />
      <textarea
        id={@id}
        name={@name}
        aria-invalid={@errors != [] || nil}
        class={[textarea_component_field_class(), @class]}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <.component_field_error :for={msg <- @errors} message={msg} />
      <.component_field_hint :if={@hint} hint={@hint} />
    </div>
    """
  end

  defp textarea_component_field_class(),
    do:
      "flex field-sizing-content min-h-16 w-full rounded-lg border border-input bg-transparent px-2.5 py-2 text-base transition-colors outline-none placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 disabled:cursor-not-allowed disabled:bg-input/50 disabled:opacity-50 aria-invalid:border-destructive aria-invalid:ring-3 aria-invalid:ring-destructive/20 md:text-sm"

  defp component_field_header(assigns) do
    ~H"""
    <div class="mb-1.5 flex items-center gap-1.5">
      <.icon :if={@icon} name={@icon} class="size-3.5 text-muted-foreground" />
      <label for={@id} class="text-sm font-medium text-foreground/90">{@label}</label>
    </div>
    """
  end

  defp component_field_hint(assigns) do
    ~H"""
    <p class="mt-1.5 text-xs text-muted-foreground">{@hint}</p>
    """
  end

  attr :message, :string, required: true

  defp component_field_error(assigns) do
    ~H"""
    <p class="mt-1.5 text-xs font-medium text-destructive">{@message}</p>
    """
  end

  defp assign_component_field(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))
  end

  defp assign_component_field(assigns), do: assigns

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders a policy rule pill. Color reflects `action` (`block` / `warn` /
  `escalate_to_human`); the label content goes in the inner block.

  ## Examples

      <.rule_tag action="block" class="px-2.5 py-1 text-xs font-medium">no rm rf</.rule_tag>
  """
  attr :action, :string, required: true
  attr :title, :string, default: nil
  attr :class, :any, default: nil, doc: "spacing/typography classes appended to the pill"
  slot :inner_block, required: true, doc: "rule label"

  def rule_tag(assigns) do
    ~H"""
    <span
      title={@title}
      class={["inline-flex rounded-full ring-1", rule_tag_class(@action), @class]}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp rule_tag_class("block"), do: "bg-destructive/10 text-destructive ring-destructive/20"
  defp rule_tag_class("warn"), do: "bg-warning/10 text-warning ring-warning/20"
  defp rule_tag_class("escalate_to_human"), do: "bg-info/10 text-info ring-info/20"
  defp rule_tag_class(_), do: "bg-muted text-muted-foreground ring-border"

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Renders a modal dialog shell: overlay, Escape-to-close, close button, and
  focus-on-open. Content goes in the inner block; the LiveView owning the
  modal handles the `on_close` event by toggling its open assign.

  ## Examples

      <.modal id="my-modal" title="Title" on_close="close_modal">
        body
      </.modal>
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :on_close, :string, required: true, doc: "event pushed on backdrop click, X, or Escape"
  attr :width, :string, default: "max-w-2xl"
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      class="relative z-50"
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
      phx-mounted={JS.show(to: "##{@id}") |> JS.focus_first(to: "##{@id}")}
      phx-remove={JS.hide(to: "##{@id}")}
      phx-window-keydown={JS.push(@on_close)}
      phx-key="escape"
    >
      <div
        class="fixed inset-0 bg-overlay/70 backdrop-blur-sm transition-opacity"
        phx-click={@on_close}
        aria-hidden="true"
      />
      <div class="fixed inset-0 flex items-center justify-center p-4">
        <div class={"max-h-[90vh] w-full overflow-y-auto rounded-2xl border bg-card p-6 shadow-card #{@width}"}>
          <div class="mb-5 flex items-center justify-between">
            <h2 id={"#{@id}-title"} class="text-lg font-semibold text-foreground">
              {@title}
            </h2>
            <button
              type="button"
              phx-click={@on_close}
              class="rounded-md text-muted-foreground transition hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 focus-visible:ring-offset-background"
              aria-label="Close"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(ControlKeelWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(ControlKeelWeb.Gettext, "errors", msg, opts)
    end
  end
end

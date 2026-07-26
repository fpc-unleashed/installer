// Shared body for TPixieMarkdownView across Lazarus, VCL, and FMX
// platforms. Each platform .pas file declares the class as a subclass
// of its own TPixieHtmlViewBase, then includes this file inside the
// class body. The corresponding implementation lives in
// Pixie.MarkdownView.impl.inc.

  private
    FMarkdown: TStringList;
    FUseDefaultStyles: Boolean;
    FBaseUrl: string;
    function GetMarkdown: TStrings;
    procedure SetMarkdown(Value: TStrings);
    procedure SetUseDefaultStyles(Value: Boolean);
    procedure DoMarkdownChange(Sender: TObject);
    procedure RebuildHtml;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure LoadMarkdownFromString(const AMd: string;
      const ABaseUrl: string = '');
    procedure LoadMarkdownFromFile(const AFileName: string);
    procedure LoadMarkdownFromStream(AStream: TStream;
      const ABaseUrl: string = '');

    procedure SaveAsPng(const FileName: string;
      Width: Integer; Height: Integer = 0); overload;
    procedure SaveAsPng(Stream: TStream;
      Width: Integer; Height: Integer = 0); overload;
    procedure SaveAsBmp(const FileName: string;
      Width: Integer; Height: Integer = 0); overload;
    procedure SaveAsBmp(Stream: TStream;
      Width: Integer; Height: Integer = 0); overload;
  published
    property Markdown: TStrings read GetMarkdown write SetMarkdown;
    property UseDefaultStyles: Boolean read FUseDefaultStyles
      write SetUseDefaultStyles default True;

unit Pixie.HtmlView.FMX;

// TPixieHtmlView — Delphi FMX visual component that renders HTML content
// using the Pixie engine with FireMonkey graphics. Enables cross-platform
// HTML rendering on Windows, macOS, iOS, and Android.

interface

uses
  System.Classes, System.SysUtils,
  Pixie.HtmlView.FMX.Base;

type
  { TPixieHtmlView }

  TPixieHtmlView = class(TPixieHtmlViewBase)
  public
    procedure LoadFromString(const AHtml: string;
      const ABaseUrl: string = '');
    procedure LoadFromFile(const AFileName: string;
      const ABaseUrl: string = '');
    procedure LoadFromStream(AStream: TStream;
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
    property Lines: TStrings read GetLines write SetLines;
  end;

implementation

procedure TPixieHtmlView.LoadFromString(const AHtml: string;
  const ABaseUrl: string);
begin
  CoreLoadFromString(AHtml, ABaseUrl);
end;

procedure TPixieHtmlView.LoadFromFile(const AFileName: string;
  const ABaseUrl: string);
begin
  CoreLoadFromFile(AFileName, ABaseUrl);
end;

procedure TPixieHtmlView.LoadFromStream(AStream: TStream;
  const ABaseUrl: string);
begin
  CoreLoadFromStream(AStream, ABaseUrl);
end;

procedure TPixieHtmlView.SaveAsPng(const FileName: string;
  Width, Height: Integer);
begin
  CoreSaveAsPng(FileName, Width, Height);
end;

procedure TPixieHtmlView.SaveAsPng(Stream: TStream; Width, Height: Integer);
begin
  CoreSaveAsPng(Stream, Width, Height);
end;

procedure TPixieHtmlView.SaveAsBmp(const FileName: string;
  Width, Height: Integer);
begin
  CoreSaveAsBmp(FileName, Width, Height);
end;

procedure TPixieHtmlView.SaveAsBmp(Stream: TStream; Width, Height: Integer);
begin
  CoreSaveAsBmp(Stream, Width, Height);
end;

end.

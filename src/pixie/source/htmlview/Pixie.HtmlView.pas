unit Pixie.HtmlView;

// TPixieHtmlView — Lazarus visual component that renders HTML content
// using the Pixie engine with platform-native graphics.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Classes, SysUtils,
  Pixie.HtmlView.Base;

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

    // Width is the layout viewport. Height=0 uses computed content
    // height after layout. Transparent background.
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

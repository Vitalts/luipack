unit PresentationManager;

{$mode objfpc}{$H+}

interface

uses
  Forms, Classes, SysUtils, contnrs, Controls;

type

  { TPresenter }

  TPresenter = class(TComponent)
  protected
    procedure Initialize; virtual;
    function GetViewCaption(const DesignCaption: String): String; virtual;
  public
  end;

  TPresenterClass = class of TPresenter;

  IPresentation = interface
    ['{5FFDE1D3-AA0B-43C9-8ED3-437E33806B15}']
    function CallMethod(const MethodName: String): IPresentation;
    function GetName: String;
    function SetParent(Parent: TWinControl): IPresentation;
    function SetProperties(const Properties: array of const): IPresentation;
    function Show: IPresentation;
    function ShowModal: IPresentation;
    function ShowModal(const Properties: array of const): TModalResult;
    function ModalResult: TModalResult;
  end;

  { IPresentationManager }

  IPresentationManager = interface
    ['{25532926-50FF-42F3-800D-AB4A7B01B3BA}']
    function GetPresentation(const PresentationName: String): IPresentation;
    procedure Register(const PresentationName: String; ViewClass: TFormClass; PresenterClass: TPresenterClass = nil);
    procedure Register(const PresentationName: String; ViewClass: TFormClass;
      const DefaultProperties: array of const);
    procedure Register(const PresentationName: String; ViewClass: TFormClass; PresenterClass: TPresenterClass;
      const DefaultProperties: array of const);
    property Items[const PresentationName: String]: IPresentation read GetPresentation; default;
  end;

  TPresentationCreateEvent = procedure(Presentation: IPresentation) of object;

  { TPresentationManager }

  TPresentationManager = class(TComponent, IPresentationManager)
  private
    FOnPresentationCreate: TPresentationCreateEvent;
    FPresentationDefs: TFPHashObjectList;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function GetPresentation(const PresentationName: String): IPresentation;
    procedure Register(const PresentationName: String; ViewClass: TFormClass;
      PresenterClass: TPresenterClass = nil); inline;
    procedure Register(const PresentationName: String; ViewClass: TFormClass;
      const DefaultProperties: array of const); inline;
    procedure Register(const PresentationName: String; ViewClass: TFormClass; PresenterClass: TPresenterClass;
      const DefaultProperties: array of const);
    property Items[const PresentationName: String]: IPresentation read GetPresentation; default;
    property OnPresentationCreate: TPresentationCreateEvent read FOnPresentationCreate write FOnPresentationCreate;
  end;

implementation

uses
  LuiRTTIUtils, typinfo, LuiMiscUtils, VarRecUtils;

type

  { TPresentationDef }

  TPresentationDef = class
  private
    FPresenterClass: TPresenterClass;
    FViewClass: TFormClass;
    FDefaultProperties: TConstArray;
  public
    destructor Destroy; override;
  end;

  { TPresentation }

  TPresentation = class(TInterfacedObject, IPresentation)
  private
    FName: String;
    FPresenter: TPresenter;
    FView: TForm;
    FModalResult: TModalResult;
    FInitialized: Boolean;
    procedure Initialize;
    procedure InitializeProperties;
  public
    constructor Create(const Name: String; PresentationDef: TPresentationDef);
    destructor Destroy; override;
    function CallMethod(const AMethodName: String): IPresentation;
    function GetName: String;
    function ModalResult: TModalResult;
    function SetParent(Parent: TWinControl): IPresentation;
    function SetProperties(const Properties: array of const): IPresentation;
    function Show: IPresentation;
    function ShowModal: IPresentation;
    function ShowModal(const Properties: array of const): TModalResult;
  end;

{ TPresentationDef }

destructor TPresentationDef.Destroy;
begin
  FinalizeConstArray(FDefaultProperties);
  inherited Destroy;
end;

{ TPresenter }

procedure TPresenter.Initialize;
begin
  //
end;

function TPresenter.GetViewCaption(const DesignCaption: String): String;
begin
  Result := DesignCaption;
end;

{ TPresentation }

procedure TPresentation.Initialize;
begin
  if FInitialized then
    Exit;
  InitializeProperties;
  if FPresenter <> nil then
  begin
    FPresenter.Initialize;
    FView.Caption := FPresenter.GetViewCaption(FView.Caption);
  end;
  LuiMiscUtils.CallMethod(FView, 'Initialize');
  FInitialized := True;
end;

procedure BindProperty(Instance: TObject; const PropName: String; PropInstance: TObject);
var
  PropInfo: PPropInfo;
  TypeData: PTypeData;
  Intf: IInterface;
begin
  PropInfo := GetPropInfo(Instance, PropName);
  if PropInfo <> nil then
  begin
    if PropInstance = nil then
      raise Exception.CreateFmt('%s requires a %s', [Instance.ClassName, PropName]);
    TypeData := GetTypeData(PropInfo^.PropType);
    case PropInfo^.PropType^.Kind of
      tkInterface:
        begin
          if not PropInstance.GetInterface(TypeData^.GUID, Intf) then
            raise Exception.CreateFmt('%s requires a %s that implements %s',
              [Instance.ClassName, PropName, GUIDToString(TypeData^.GUID)]);
          SetInterfaceProp(Instance, PropInfo, Intf);
        end;
      tkClass:
        begin
          if not PropInstance.InheritsFrom(TypeData^.ClassType) then
            raise Exception.CreateFmt('%s requires a %s that inherits from %s',
              [Instance.ClassName, PropName, TypeData^.ClassType.ClassName]);
          SetObjectProp(Instance, PropInfo, PropInstance);
        end;
      else
        raise Exception.CreateFmt('%s - %s property must be a COM interface or a class',
          [Instance.ClassName, PropName]);
    end;
  end;
end;

procedure TPresentation.InitializeProperties;
begin
  BindProperty(FView, 'Presenter', FPresenter);
  if FPresenter <> nil then
    BindProperty(FPresenter, 'View', FView);
end;

constructor TPresentation.Create(const Name: String;
  PresentationDef: TPresentationDef);
begin
  FView := PresentationDef.FViewClass.Create(nil);
  if PresentationDef.FPresenterClass <> nil then
    FPresenter := PresentationDef.FPresenterClass.Create(FView);
  FName := Name;
  SetProperties(PresentationDef.FDefaultProperties);
end;

destructor TPresentation.Destroy;
begin
  FView.Free;
  inherited Destroy;
end;

function TPresentation.CallMethod(const AMethodName: String): IPresentation;
begin
  if FPresenter <> nil then
    LuiMiscUtils.CallMethod(FPresenter, AMethodName);
  LuiMiscUtils.CallMethod(FView, AMethodName);
  Result := Self;
end;

function TPresentation.ModalResult: TModalResult;
begin
  Result := FModalResult;
end;

function TPresentation.GetName: String;
begin
  Result := FName;
end;

function TPresentation.SetParent(Parent: TWinControl): IPresentation;
begin
  FView.Parent := Parent;
  if Parent <> nil then
  begin
    FView.BorderStyle := bsNone;
    FView.Align := alClient;
  end
  else
  begin
    //todo: save restore BorderStyle
  end;
  Result := Self;
end;

function TPresentation.SetProperties(
  const Properties: array of const): IPresentation;
begin
  if FPresenter <> nil then
    SetObjectProperties(FPresenter, Properties);
  SetObjectProperties(FView, Properties);
  Result := Self;
end;

function TPresentation.Show: IPresentation;
begin
  Initialize;
  FView.Show;
  Result := Self;
end;

function TPresentation.ShowModal: IPresentation;
begin
  if FView.Parent <> nil then
    raise Exception.Create('Is not allowed to show modal form with parent');
  Initialize;
  //todo: add presenter afterviewshow?
  FModalResult := FView.ShowModal;
  Result := Self;
end;

function TPresentation.ShowModal(const Properties: array of const): TModalResult;
begin
  Result := SetProperties(Properties).ShowModal.ModalResult;
end;

{ TPresentationManager }

constructor TPresentationManager.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPresentationDefs := TFPHashObjectList.Create(True);
end;

destructor TPresentationManager.Destroy;
begin
  FPresentationDefs.Destroy;
  inherited Destroy;
end;

function TPresentationManager.GetPresentation(const PresentationName: String): IPresentation;
var
  PresentationDef: TPresentationDef;
begin
  PresentationDef := TPresentationDef(FPresentationDefs.Find(PresentationName));
  if PresentationDef = nil then
    raise Exception.CreateFmt('Presentation "%s" not found', [PresentationName]);
  Result := TPresentation.Create(PresentationName, PresentationDef);
  if Assigned(FOnPresentationCreate) then
    FOnPresentationCreate(Result);
end;

procedure TPresentationManager.Register(const PresentationName: String;
  ViewClass: TFormClass; PresenterClass: TPresenterClass);
begin
  Register(PresentationName, ViewClass, PresenterClass, []);
end;

procedure TPresentationManager.Register(const PresentationName: String;
  ViewClass: TFormClass; const DefaultProperties: array of const);
begin
  Register(PresentationName, ViewClass, nil, DefaultProperties);
end;

procedure TPresentationManager.Register(const PresentationName: String;
  ViewClass: TFormClass; PresenterClass: TPresenterClass;
  const DefaultProperties: array of const);
var
  PresentationDef: TPresentationDef;
begin
  if ViewClass = nil then
    raise Exception.CreateFmt('Unable to register "%s" presentation: ViewClass must be <> nil', [PresentationName]);
  if FPresentationDefs.FindIndexOf(PresentationName) <> -1 then
    raise Exception.CreateFmt('Presentation "%s" already registered', [PresentationName]);
  PresentationDef := TPresentationDef.Create;
  PresentationDef.FViewClass := ViewClass;
  PresentationDef.FPresenterClass := PresenterClass;
  PresentationDef.FDefaultProperties := CreateConstArray(DefaultProperties);
  FPresentationDefs.Add(PresentationName, PresentationDef);
end;


end.


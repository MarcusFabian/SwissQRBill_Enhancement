pageextension 50400 "Enh QR Purchase Invoice" extends "Purchase Invoice"
{
    layout { }

    actions
    {
        modify("Swiss QR-Bill Scan")
        {
            Promoted = false;
        }

        addfirst(processing)
        {
            group("Enhanced QR Scan")
            {
                Action(QRScan)
                {
                    Caption = 'QR-Code lesen';
                    ToolTip = 'QR-Code scanen und für die Rechnung interpretieren';
                    ApplicationArea = All;
                    Image = Import;
                    PromotedCategory = Process;
                    Promoted = true;
                    trigger OnAction()
                    var
                        QRScanPage: Page "QR-Scan";
                        QREnhancement: Codeunit "QR Enhancement";
                    begin
                        clear(QRscanPage);
                        if QRScanPage.RunModal() = Action::OK then begin
                            QRCodeText := QRScanPage.GetQRBillText();
                            QREnhancement.DecodeQRCodeIntoBuffer(QRCodeText, qrbuffer);
                        end;
                    end;
                }
            }
        }
    }
    var
        QRCodeText: Text;
        QRBuffer:  Record "Swiss QR-Bill Buffer" temporary;
}




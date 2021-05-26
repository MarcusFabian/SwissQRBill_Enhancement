page 50400 "QR-Scan"
{
    Caption = 'QR-Bill Scan';
    PageType = Card;

    layout
    {
        area(Content)
        {
            group(General)
            {
                field(QRCodeTextField; QRCodeText)
                {
                    Caption = 'QR-Code Input';
                    ToolTip = 'Specifies the QR-Code text or scan.';
                    ApplicationArea = All;
                    MultiLine = true;
                }
            }
        }
    }

    var
        QRCodeText: Text;

    internal procedure GetQRBillText(): Text
    begin
        exit(QRCodeText);
    end;
}


codeunit 50400 "QR Enhancement"
{
    var
        TempNameValueBuffer: Record "Name/Value Buffer" temporary;
        ErrorLogContextRecordId: RecordId;
        CurrentLineNo: Integer;
        HeaderSPCValueNotFoundLbl: Label 'Header QR type value SPC is not found.';
        HeaderVersionValueNotFoundLbl: Label 'Header version value 0200 is not found.';
        HeaderCodingTypeNotFoundLbl: Label 'Header coding type value 1 is not found.';
        CreditorIBANNotFoundLbl: Label 'Creditor''s account value (IBAN or QR-IBAN) is not found.';
        CreditorIBANLengthLbl: Label 'Creditor''s account value (IBAN or QR-IBAN) should be 21 chars length.';
        CreditorIBANCountryLbl: Label 'Only CH and LI IBAN values are permitted.';
        ParseAmountFailedLbl: Label 'Failed to parse amount value.';
        CurrencyNotFoundLbl: Label 'Currency is not found.';
        WrongCurrencyLbl: Label 'Only CHF and EUR currencies are permitted.';
        PmtReferenceTypeNotFoundLbl: Label 'Payment reference type is not found.';
        UnknownPmtReferenceTypeLbl: Label 'Payment reference type (QRR, SCOR or NON) is not found.';
        QRReferenceLengthLbl: Label 'QR-Reference must be 27 chars length.';
        CreditorReferenceLengthLbl: Label 'Creditor-Reference must be up to 25 chars length and start with RF and two check digits.';
        BlankedReferenceExpectedLbl: Label 'Blanked reference number is expected for reference type NON.';
        AddressTypeNotFoundLbl: Label 'Address type "S" or "K" is not found.';
        NameNotFoundLbl: Label 'The Name value is not found.';
        ExpectedBlankedValueLbl: Label 'The line value is expected to be blanked.';
        ExpectedEOFLbl: Label 'Unexpected end of file.';
        FileLineLbl: Label 'File line %1: %2', Comment = '%1 - line number, %2 - line text message';
        EmptyFileLbl: Label 'The file is empty.';
        UnstrMsgNotFoundLbl: Label 'Unstructured message is not found.';
        TrailerEPDNotFoundLbl: Label 'Trailer value EPD is not found.';
        IsAnyErrorLog: Boolean;

    internal procedure AnyErrorLogged(): Boolean
    begin
        exit(IsAnyErrorLog);
    end;

    procedure DecodeQRCodeIntoBuffer(Var QRCodeText: Text; Var QRBuffer: Record "Swiss QR-Bill Buffer"): Boolean
    var
        Handled: Boolean;
    begin
        Handled := false;
        Clear(QRBuffer);
        OnBeforeDecodeQRCodeIntoBuffer(QRCodeText, QRBuffer, Handled);
        if Handled then
            exit;

        if not InitializeLineBuffer(QRCodeText) then
            exit(false);

        if not ReadHeader() then
            exit(false);
        if not ReadIBAN(QRBuffer) then
            exit(false);
        if not ReadCreditorPartyInfo(QRBuffer) then
            exit(false);
        if not ReadUltimateCreditorPartyInfo(QRBuffer) then
            exit(false);
        if not ReadPaymentInfo(QRBuffer) then
            exit(false);
        if not ReadUltimateDebitorPartyInfo(QRBuffer) then
            exit(false);
        if not ReadPaymentReferenceInfo(QRBuffer) then
            exit(false);
        if not ReadNextLineIntoFieldNo(QRBuffer, QRBuffer.FieldNo("Unstructured Message"), UnstrMsgNotFoundLbl) then
            exit(false);
        if not ReadNextLineAndAssertValue('EPD', TrailerEPDNotFoundLbl) then
            exit(false);
        // Optional
        if not ReadNextLineIntoFieldNo(QRBuffer, QRBuffer.FieldNo("Billing Information"), '') then
            exit(not AnyErrorLogged());
        if not ReadNextLineIntoFieldNo(QRBuffer, QRBuffer.FieldNo("Alt. Procedure Value 1"), '') then
            exit(not AnyErrorLogged());
        ReadNextLineIntoFieldNo(QRBuffer, QRBuffer.FieldNo("Alt. Procedure Value 2"), '');
        ParseAltProcedures(QRBuffer);
        exit(not AnyErrorLogged());

        OnAfterDecodeQRCodeIntoBuffer(QRCodeText, QRBuffer);
    end;

    local procedure ParseAltProcedures(var QRBuffer: Record "Swiss QR-Bill Buffer")
    begin
        with QRBuffer do begin
            ParseAltProcedure("Alt. Procedure Name 1", "Alt. Procedure Value 1", 'AV1');
            ParseAltProcedure("Alt. Procedure Name 2", "Alt. Procedure Value 2", 'AV2');
        end;
    end;

    local procedure ParseAltProcedure(var NameText: Text[10]; var ValueText: Text[100]; defaultName: Text[10])
    var
        Pos: Integer;
    begin
        if ValueText <> '' then begin
            Pos := StrPos(ValueText, ':');
            if (Pos > 1) and (Pos <= (MaxStrLen(NameText) + 1)) then begin
                NameText := CopyStr(CopyStr(ValueText, 1, Pos - 1), 1, MaxStrLen(NameText));
                ValueText := CopyStr(DelStr(ValueText, 1, Pos + 1), 1, MaxStrLen(ValueText));
            end else
                NameText := defaultName;
        end;
    end;

    local procedure InitializeLineBuffer(QRCodeText: Text): Boolean
    var
        TempBlob: Codeunit "Temp Blob";
        InStream: InStream;
        OutStream: OutStream;
        LineText: Text;
        MaxLineNo: Integer;
        EmptyBuffer: Boolean;
    begin
        MaxLineNo := 100;
        CurrentLineNo := 0;
        if StrLen(QRCodeText) = 0 then
            exit(LogErrorAndExit(EmptyFileLbl, true, false));

        TempBlob.CreateOutStream(OutStream);
        TempBlob.CreateInStream(InStream);
        OutStream.Write(QRCodeText);

        TempNameValueBuffer.Init();
        while not InStream.EOS() and (TempNameValueBuffer.ID < MaxLineNo) do begin
            TempNameValueBuffer.ID += 1;
            InStream.ReadText(LineText);
            TempNameValueBuffer.Value := CopyStr(LineText, 1, MaxStrLen(TempNameValueBuffer.Value));
            TempNameValueBuffer.Insert();
        end;

        EmptyBuffer := TempNameValueBuffer.IsEmpty();
        exit(LogErrorAndExit(EmptyFileLbl, EmptyBuffer, not EmptyBuffer));
    end;

    local procedure ReadHeader(): Boolean
    begin
        if not ReadNextLineAndAssertValue('SPC', HeaderSPCValueNotFoundLbl) then
            exit(false);

        if not ReadNextLineAndAssertValue('0200', HeaderVersionValueNotFoundLbl) then
            exit(false);

        exit(ReadNextLineAndAssertValue('1', HeaderCodingTypeNotFoundLbl));
    end;

    local procedure ReadIBAN(var QRBuffer: Record "Swiss QR-Bill Buffer"): Boolean
    var
        LineText: Text;
    begin
        if not ReadNextLineAndTestValue(LineText, CreditorIBANNotFoundLbl) then
            exit(false);

        if CheckIBAN(LineText) then
            QRBuffer.IBAN := CopyStr(LineText, 1, MaxStrLen(QRBuffer.IBAN));
        exit(true);
    end;

    local procedure CheckIBAN(var IBAN: Text): Boolean
    begin
        IBAN := DelChr(IBAN);
        if StrLen(IBAN) <> 21 then
            exit(LogErrorAndExit(CreditorIBANLengthLbl, true, false));

        if not (CopyStr(IBAN, 1, 2) in ['CH', 'LI']) then
            exit(LogErrorAndExit(CreditorIBANCountryLbl, true, false));

        exit(true);
    end;

    local procedure ReadCreditorPartyInfo(var QRBuffer: Record "Swiss QR-Bill Buffer"): Boolean
    var
        TempCustomer: Record Customer temporary;
        AddressType: Text;
    begin
        if not ReadPartyInfo(TempCustomer, AddressType, true) then
            exit(false);

        SetCreditorInfo(Qrbuffer, TempCustomer);
        QRBuffer."Creditor Address Type" := MapAddressType(AddressType);
        exit(true);
    end;

    local procedure ReadUltimateCreditorPartyInfo(var QRBuffer: Record "Swiss QR-Bill Buffer"): Boolean
    var
        TempCustomer: Record Customer temporary;
        AddressType: Text;
    begin
        if not ReadPartyInfo(TempCustomer, AddressType, false) then
            exit(false);

        if AddressType <> '' then begin
            SetUltimateCreditorInfo(QRBuffer, TempCustomer);
            QRBuffer."UCreditor Address Type" := MapAddressType(AddressType);
        end;
        exit(true);
    end;

    local procedure ReadPaymentInfo(var QRBuffer: Record "Swiss QR-Bill Buffer"): Boolean
    var
        AmountText: Text;
        CurrencyText: Text;
    begin
        if not ReadNextLine(AmountText, true) then
            exit(false);
        if AmountText <> '' then
            if not Evaluate(QRBuffer.Amount, DelChr(AmountText), 9) then
                LogErrorAndExit(ParseAmountFailedLbl, true, false);
        if not ReadNextLineAndTestValue(CurrencyText, CurrencyNotFoundLbl) then
            exit(false);
        QRBuffer.Currency := CopyStr(CurrencyText, 1, 3);
        exit(LogErrorAndExit(WrongCurrencyLbl, not AllowedISOCurrency(CurrencyText), true));
    end;

    local procedure ReadUltimateDebitorPartyInfo(var QRBuffer: Record "Swiss QR-Bill Buffer"): Boolean
    var
        TempCustomer: Record Customer temporary;
        AddressType: Text;
    begin
        if not ReadPartyInfo(TempCustomer, AddressType, false) then
            exit(false);

        if AddressType <> '' then begin
            SetUltimateDebitorInfo(QRBuffer, TempCustomer);
            QRBuffer."UDebtor Address Type" := MapAddressType(AddressType);
        end;
        exit(true);
    end;

    local procedure ReadPaymentReferenceInfo(var QRBuffer: Record "Swiss QR-Bill Buffer"): Boolean
    var
        ReferenceTypeText: Text;
    begin
        if not ReadNextLineAndTestValue(ReferenceTypeText, PmtReferenceTypeNotFoundLbl) then
            exit(false);

        with QRBuffer do
            case ReferenceTypeText of
                'QRR':
                    begin
                        "IBAN Type" := "IBAN Type"::"QR-IBAN";
                        "Payment Reference Type" := "Payment Reference Type"::"QR Reference";
                    end;
                'SCOR':
                    begin
                        "IBAN Type" := "IBAN Type"::IBAN;
                        "Payment Reference Type" := "Payment Reference Type"::"Creditor Reference (ISO 11649)";
                    end;
                'NON':
                    "Payment Reference Type" := "Payment Reference Type"::"Without Reference";
                else
                    LogErrorAndExit(UnknownPmtReferenceTypeLbl, true, false);
            end;

        exit(ReadCheckAndValidateReferenceNo(QRBuffer));
    end;

    local procedure ReadCheckAndValidateReferenceNo(var SwissQRBillBuffer: Record "Swiss QR-Bill Buffer"): Boolean
    var
        PaymentReferenceNoText: Text;
    begin
        if not ReadNextLine(PaymentReferenceNoText, true) then
            exit(false);

        PaymentReferenceNoText := DelChr(PaymentReferenceNoText);
        with SwissQRBillBuffer do begin
            case "Payment Reference Type" of
                "Payment Reference Type"::"QR Reference":
                    if StrLen(PaymentReferenceNoText) <> 27 then
                        exit(LogErrorAndExit(QRReferenceLengthLbl, true, true));
                "Payment Reference Type"::"Creditor Reference (ISO 11649)":
                    if (StrLen(PaymentReferenceNoText) > 25) or
                       (StrLen(PaymentReferenceNoText) < 5) or
                       (CopyStr(PaymentReferenceNoText, 1, 2) <> 'RF')
                    then
                        exit(LogErrorAndExit(CreditorReferenceLengthLbl, true, true));
                "Payment Reference Type"::"Without Reference":
                    if StrLen(PaymentReferenceNoText) > 0 then
                        exit(LogErrorAndExit(BlankedReferenceExpectedLbl, true, true));
            end;
            "Payment Reference" := CopyStr(PaymentReferenceNoText, 1, MaxStrLen("Payment Reference"));
        end;

        exit(true);
    end;


    local procedure ReadPartyInfo(var Customer: Record Customer; var AddressType: Text; Mandatory: Boolean): Boolean
    var
        NewName: Text;
        AddressLine1: Text;
        AddressLine2: Text;
        PostalCode: Text;
        NewCity: Text;
        Country: Text;
        i: Integer;
    begin
        Clear(Customer);

        if not ReadNextLine(AddressType, true) then
            exit(false);

        if not Mandatory and (AddressType = '') then
            exit(ReadBlankedPartyInfo());

        if not (AddressType in ['S', 'K']) then
            LogErrorAndExit(AddressTypeNotFoundLbl, true, false);

        if not ReadNextLineAndTestValue(NewName, NameNotFoundLbl) then
            exit(false);
        if not ReadNextLine(AddressLine1, true) then
            exit(false);
        if not ReadNextLine(AddressLine2, true) then
            exit(false);
        if AddressType = 'S' then begin
            if not ReadNextLine(PostalCode, true) then
                exit(false);
            if not ReadNextLine(NewCity, true) then
                exit(false);
        end else
            for i := 1 to 2 do
                if not ReadNextLineAndAssertValue('', ExpectedBlankedValueLbl) then
                    exit(false);
        if not ReadNextLine(Country, true) then
            exit(false);

        with Customer do begin
            Name := CopyStr(NewName, 1, MaxStrLen(Name));
            Address := CopyStr(AddressLine1, 1, MaxStrLen(Address));
            "Address 2" := CopyStr(AddressLine2, 1, MaxStrLen("Address 2"));
            if AddressType = 'S' then begin
                "Post Code" := CopyStr(PostalCode, 1, MaxStrLen("Post Code"));
                City := CopyStr(NewCity, 1, MaxStrLen(City));
            end;
            "Country/Region Code" := CopyStr(Country, 1, MaxStrLen("Country/Region Code"));
        end;

        exit(true);
    end;

    local procedure MapAddressType(AddressType: Text) Result: Enum "Swiss QR-Bill Address Type"
    begin
        if AddressType = 'S' then
            exit(Result::Structured);
        exit(Result::Combined);
    end;

    local procedure ReadBlankedPartyInfo(): Boolean
    var
        i: Integer;
    begin
        for i := 1 to 6 do
            if not ReadNextLineAndAssertValue('', ExpectedBlankedValueLbl) then
                exit(false);
        exit(true);
    end;

    local procedure ReadNextLineIntoFieldNo(var QRBuffer: Record "Swiss QR-Bill Buffer"; FieldNo: Integer; ErrorDescription: Text): Boolean
    var
        RecordRef: RecordRef;
        FieldRef: FieldRef;
        LineText: Text;
    begin
        if not ReadNextLine(LineText, ErrorDescription <> '') then
            exit(LogErrorAndExit(ErrorDescription, true, false));

        RecordRef.GetTable(QRBuffer);
        FieldRef := RecordRef.Field(FieldNo);
        FieldRef.Value := CopyStr(LineText, 1, FieldRef.Length());
        RecordRef.SetTable(QRBuffer);
        exit(true);
    end;

    local procedure ReadNextLine(var LineText: Text; LogEOF: Boolean) FileRead: Boolean
    begin
        if CurrentLineNo = 0 then
            FileRead := TempNameValueBuffer.FindSet()
        else
            FileRead := TempNameValueBuffer.Next() <> 0;

        CurrentLineNo += 1;
        LineText := TempNameValueBuffer.Value;
        exit(LogErrorAndExit(ExpectedEOFLbl, not FileRead and LogEOF, FileRead));
    end;

    local procedure ReadNextLineAndTestValue(var LineText: Text; ErrorDescription: Text) Result: Boolean
    begin
        Result := ReadNextLine(LineText, true);
        exit(LogErrorAndExit(ErrorDescription, Result and (LineText = ''), Result));
    end;

    local procedure ReadNextLineAndAssertValue(ExpectedValue: Text; ErrorDescription: Text) Result: Boolean
    var
        LineText: Text;
    begin
        Result := ReadNextLine(LineText, true);
        exit(LogErrorAndExit(ErrorDescription, Result and (LineText <> ExpectedValue), Result));
    end;


    local procedure LogErrorAndExit(ErrorDescription: Text; ErrorCondition: Boolean; Result: Boolean): Boolean
    var
        ErrorMessage: Record "Error Message";
    begin
        exit(LogAndExit(ErrorMessage."Message Type"::Error, ErrorDescription, ErrorCondition, Result));
    end;

    local procedure LogAndExit(MessageType: Option; MessageDescription: Text; MessageCondition: Boolean; Result: Boolean): Boolean
    var
        ErrorMessage: Record "Error Message";
    begin
        if MessageCondition and (MessageDescription <> '') then
            if ErrorLogContextRecordId.TableNo() <> 0 then begin
                ErrorMessage.SetContext(ErrorLogContextRecordId);
                if CurrentLineNo > 0 then
                    MessageDescription := StrSubstNo(FileLineLbl, CurrentLineNo, MessageDescription);
                ErrorMessage.LogSimpleMessage(MessageType, MessageDescription);
                IsAnyErrorLog := true;
            end;
        exit(Result);
    end;

    internal procedure SetUltimateDebitorInfo(Var QRBuffer: Record "Swiss QR-Bill Buffer"; Customer: Record Customer)
    var
        Language: Codeunit Language;
        LanguageId: Integer;
    begin
        QRBuffer."UDebtor Name" := CopyStr(Customer.Name, 1, MaxStrLen(QRBuffer."Creditor Name"));
        QRBuffer."UDebtor Street Or AddrLine1" := CopyStr(Customer.Address, 1, MaxStrLen(QRBuffer."Creditor Street Or AddrLine1"));
        QRBuffer."UDebtor BuildNo Or AddrLine2" := CopyStr(Customer."Address 2", 1, MaxStrLen(QRBuffer."Creditor BuildNo Or AddrLine2"));
        QRBuffer."UDebtor Postal Code" := CopyStr(Customer."Post Code", 1, MaxStrLen(QRBuffer."Creditor Postal Code"));
        QRBuffer."UDebtor City" := Customer.City;
        QRBuffer."UDebtor Country" := CopyStr(Customer."Country/Region Code", 1, MaxStrLen(QRBuffer."Creditor Country"));

        LanguageId := Language.GetLanguageId(Customer."Language Code");
        case true of
            GetLanguagesIdDEU().Contains(Format(LanguageId)):
                QRBuffer."Language Code" := Language.GetLanguageCode(GetLanguageIdDEU());
            GetLanguagesIdFRA().Contains(Format(LanguageId)):
                QRBuffer."Language Code" := Language.GetLanguageCode(GetLanguageIdFRA());
            GetLanguagesIdITA().Contains(Format(LanguageId)):
                QRBuffer."Language Code" := Language.GetLanguageCode(GetLanguageIdITA());
            else
                QRBuffer."Language Code" := Language.GetLanguageCode(GetLanguageIdENU());
        end;

    end;

    internal procedure SetCreditorInfo(Var QRBuffer: Record "Swiss QR-Bill Buffer"; Customer: Record Customer)
    begin
        QRBuffer."Creditor Name" := CopyStr(Customer.Name, 1, MaxStrLen(QRBuffer."Creditor Name"));
        QRBuffer."Creditor Street Or AddrLine1" := CopyStr(Customer.Address, 1, MaxStrLen(QRBuffer."Creditor Street Or AddrLine1"));
        QRBuffer."Creditor BuildNo Or AddrLine2" := CopyStr(Customer."Address 2", 1, MaxStrLen(QRBuffer."Creditor BuildNo Or AddrLine2"));
        QRBuffer."Creditor Postal Code" := CopyStr(Customer."Post Code", 1, MaxStrLen(QRBuffer."Creditor Postal Code"));
        QRBuffer."Creditor City" := Customer.City;
        QRBuffer."Creditor Country" := CopyStr(Customer."Country/Region Code", 1, MaxStrLen(QRBuffer."Creditor Country"));
    end;

    internal procedure SetUltimateCreditorInfo(Var QRBuffer: Record "Swiss QR-Bill Buffer"; Customer: Record Customer)
    begin
        QRBuffer."UCreditor Name" := CopyStr(Customer.Name, 1, MaxStrLen(QRBuffer."Creditor Name"));
        QRBuffer."UCreditor Street Or AddrLine1" := CopyStr(Customer.Address, 1, MaxStrLen(QRBuffer."Creditor Street Or AddrLine1"));
        QRBuffer."UCreditor BuildNo Or AddrLine2" := CopyStr(Customer."Address 2", 1, MaxStrLen(QRBuffer."Creditor BuildNo Or AddrLine2"));
        QRBuffer."UCreditor Postal Code" := CopyStr(Customer."Post Code", 1, MaxStrLen(QRBuffer."Creditor Postal Code"));
        QRBuffer."UCreditor City" := Customer.City;
        QRBuffer."UCreditor Country" := CopyStr(Customer."Country/Region Code", 1, MaxStrLen(QRBuffer."Creditor Country"));
    end;

    internal procedure AllowedISOCurrency(CurrencyText: Text): Boolean
    begin
        exit(CurrencyText in ['CHF', 'EUR']);
    end;

    internal procedure GetLanguageIdENU(): Integer
    begin
        exit(1033); // en-us
    end;

    internal procedure GetLanguageIdDEU(): Integer
    begin
        exit(2055); // de-ch
    end;

    internal procedure GetLanguageIdFRA(): Integer
    begin
        exit(4108); // fr-ch
    end;

    internal procedure GetLanguageIdITA(): Integer
    begin
        exit(2064); // it-ch
    end;

    internal procedure GetLanguagesIdDEU(): Text
    begin
        exit('1031|3079|2055');
    end;

    internal procedure GetLanguagesIdFRA(): Text
    begin
        exit('1036|2060|3084|4108');
    end;

    internal procedure GetLanguagesIdITA(): Text
    begin
        exit('1040|2064');
    end;

    internal procedure GetLanguageCodeENU(): Code[10]
    var
        Language: Codeunit Language;
    begin
        exit(Language.GetLanguageCode(GetLanguageIdENU()));
    end;

    [IntegrationEvent(false, false)]
    local procedure OnBeforeDecodeQRCodeIntoBuffer(Var QRCodeText: Text; var QRBuffer: Record "Swiss QR-Bill Buffer"; var Handled: Boolean);
    begin
    end;

    [IntegrationEvent(false, false)]
    local procedure OnAfterDecodeQRCodeIntoBuffer(Var QRCodeText: Text; var QRBuffer: Record "Swiss QR-Bill Buffer");
    begin
    end;


}

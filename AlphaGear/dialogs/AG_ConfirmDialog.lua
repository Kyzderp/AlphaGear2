--[[

Dialog to import from other servers, accounts, or characters

--]]

AGConfirmDlg = {}


------------------------------------------------------
------------------------------------------------------
local function ConfirmCallback(dialog)
    dialog.data[1]()
end

function AGConfirmDlg.Show(text, callback)
    ZO_Dialogs_ShowDialog("AG_CONFIRM_DIALOG", {callback}, {mainTextParams = {text}})
end

function AGConfirmDlg.Initialize()
    ESO_Dialogs["AG_CONFIRM_DIALOG"] = {
        title = {text = "Confirm Deletion"},
        mainText = {
            text = "<<1>>",
        },
        setup = function() end,
        buttons =
        {
            [1] = {
                text = SI_DIALOG_CONFIRM,
                callback = ConfirmCallback,
            },
            [2] = {
                text = SI_DIALOG_CANCEL,
                callback = function() end,
            }
        },
    }
end

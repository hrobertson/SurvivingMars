-- ========== THIS IS AN AUTOMATICALLY GENERATED FILE! ==========

PlaceObj('XTemplate', {
	group = "Mods",
	id = "ModsUIDialog",
	PlaceObj('XTemplateWindow', {
		'__context', function (parent, context) return PDXModsObjectCreateAndLoad() end,
		'__class', "XDialog",
		'Id', "idModsUIDialog",
		'MinWidth', 550,
		'MinHeight', 550,
		'HandleMouse', true,
		'InitialMode', "browse",
		'InternalModes', "browse, installed, details",
	}, {
		PlaceObj('XTemplateFunc', {
			'name', "UpdateActionViews(self, win)",
			'func', function (self, win)
				XDialog.UpdateActionViews(self, win)
				self:InvalidateMeasure()
			end,
		}),
		PlaceObj('XTemplateFunc', {
			'name', "Open",
			'func', function (self, ...)
				XDialog.Open(self, ...)
				if Platform.durango and not DurangoAllowUserCreatedContent then
					self:SetMode("installed")
				end
				ModsUIDialogStart()
				if not DurangoUserContentDisabledWarningShown and Platform.durango and not DurangoAllowUserCreatedContent then
					-- trigger a system message once
					CreateRealTimeThread(function()
						WaitCheckUserCreatedContentPrivilege(XPlayerActive, "show message")
						DurangoUserContentDisabledWarningShown = true
					end)
				end
			end,
		}),
		PlaceObj('XTemplateFunc', {
			'name', "OnDelete",
			'func', function (self, ...)
				ModsUIClosePopup(self)
				XDialog.OnDelete(self, ...)
				g_ParadoxModsContextObj = false
			end,
		}),
		PlaceObj('XTemplateFunc', {
			'name', "OnShortcut(self, shortcut, source)",
			'func', function (self, shortcut, source)
				if not self.context.popup_shown and self.Mode ~= "details" and not (Platform.durango and not DurangoAllowUserCreatedContent) then
					if shortcut == "LeftTrigger" then
						self:ResolveId("idBrowse"):Press()
						return "break"
					elseif shortcut == "RightTrigger" then
						self:ResolveId("idInstalled"):Press()
						return "break"
					end
				end
				return XDialog.OnShortcut(self, shortcut, source)
			end,
		}),
		PlaceObj('XTemplateWindow', {
			'__class', "XImage",
			'Dock', "box",
			'Image', "UI/Mods/background.tga",
			'ImageFit', "largest",
		}),
		PlaceObj('XTemplateWindow', {
			'__class', "XAspectWindow",
			'Fit', "smallest",
		}, {
			PlaceObj('XTemplateWindow', {
				'__class', "XFitContent",
				'IdNode', false,
				'Padding', box(108, 50, 108, 50),
				'Fit', "both",
			}, {
				PlaceObj('XTemplateFunc', {
					'name', "Open",
					'func', function (self, ...)
						XFitContent.Open(self, ...)
						self:SetPadding(GetSafeMargins(self:GetPadding()))
					end,
				}),
				PlaceObj('XTemplateWindow', {
					'__class', "XContentTemplate",
					'IdNode', false,
					'OnContextUpdate', function (self, context, ...)
						local list = self:ResolveId("idList")
						if list then
							local mode = GetDialogMode(self)
							local obj = ResolvePropObj(context)
							if mode == "browse" and obj.last_browse_y then
								obj.last_browse_y = list.OffsetY
								obj.last_browse_item = list.focused_item
							elseif mode == "installed" and obj.last_installed_y then
								obj.last_installed_y = list.OffsetY
								obj.last_installed_item = list.focused_item
							end
						end
						XContentTemplate.OnContextUpdate(self, context, ...)
					end,
				}, {
					PlaceObj('XTemplateMode', {
						'mode', "browse",
					}, {
						PlaceObj('XTemplateTemplate', {
							'__template', "ModsUIMainContent",
						}),
						}),
					PlaceObj('XTemplateMode', {
						'mode', "installed",
					}, {
						PlaceObj('XTemplateTemplate', {
							'__template', "ModsUIMainContent",
						}),
						}),
					PlaceObj('XTemplateMode', {
						'mode', "details",
					}, {
						PlaceObj('XTemplateTemplate', {
							'__template', "ModsUIModDetails",
						}),
						}),
					}),
				PlaceObj('XTemplateTemplate', {
					'__template', "ParadoxUIActionBars",
				}),
				PlaceObj('XTemplateWindow', {
					'__class', "XContentTemplate",
				}, {
					PlaceObj('XTemplateGroup', {
						'__condition', function (parent, context) return GetUIStyleGamepad() end,
					}, {
						PlaceObj('XTemplateMode', {
							'mode', "browse",
						}, {
							PlaceObj('XTemplateAction', {
								'ActionId', "open",
								'ActionName', T(170200551564, --[[XTemplate ModsUIDialog ActionName]] "Open"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "ButtonA",
								'ActionState', function (self, host)
									return ModsUIShowItemAction(host) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUISetDialogMode(host, "details", g_ParadoxModsContextObj:GetSelectedMod())
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "enable",
								'ActionName', T(754117323318, --[[XTemplate ModsUIDialog ActionName]] "Enable"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "ButtonY",
								'ActionState', function (self, host)
									return ModsUIShowItemAction(host, "enabled", false) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUIToggleEnabled(nil, host)
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "disable",
								'ActionName', T(251103844022, --[[XTemplate ModsUIDialog ActionName]] "Disable"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "ButtonY",
								'ActionState', function (self, host)
									return ModsUIShowItemAction(host, "enabled", true) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUIToggleEnabled(nil, host)
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "install",
								'ActionName', T(10121, --[[XTemplate ModsUIDialog ActionName]] "Install"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "ButtonX",
								'ActionState', function (self, host)
									if g_PopsDownloadingMods[host.context.selected_mod_id] then
										return "disabled"
									end
									return ModsUIShowItemAction(host, "installed", false) or "hidden"
								end,
								'OnAction', function (self, host, source)
									if not g_ParadoxAccountLoggedIn then
										ModsUIOpenLoginPopup(host.idContentWrapper)
									else
										ModsUIInstallMod()
									end
									host:UpdateActionViews(host)
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "uninstall",
								'ActionName', T(10122, --[[XTemplate ModsUIDialog ActionName]] "Uninstall"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "ButtonX",
								'ActionState', function (self, host)
									return ModsUIShowItemAction(host, "installed", true) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUIUninstallMod()
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "search",
								'ActionName', T(10123, --[[XTemplate ModsUIDialog ActionName]] "Search"),
								'ActionToolbar', "ActionBarRight",
								'ActionGamepad', "Back",
								'ActionState', function (self, host)
									return not ModsUIIsPopupShown(host) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUIConsoleSearch(host.idContentWrapper)
									host:UpdateActionViews(host)
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "filter",
								'ActionName', T(1000108, --[[XTemplate ModsUIDialog ActionName]] "Filter"),
								'ActionToolbar', "ActionBarRight",
								'ActionGamepad', "Start",
								'ActionState', function (self, host)
									return not ModsUIIsPopupShown(host) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUIChooseFilter(host.idContentWrapper)
									host:UpdateActionViews(host)
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "sort",
								'ActionName', T(10124, --[[XTemplate ModsUIDialog ActionName]] "Sort"),
								'ActionToolbar', "ActionBarRight",
								'ActionGamepad', "RightThumbClick",
								'ActionState', function (self, host)
									return not ModsUIIsPopupShown(host) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUIChooseSort(host.idContentWrapper)
									host:UpdateActionViews(host)
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "back",
								'ActionName', T(4165, --[[XTemplate ModsUIDialog ActionName]] "Back"),
								'ActionToolbar', "ActionBarRight",
								'ActionShortcut', "Escape",
								'ActionGamepad', "ButtonB",
								'ActionState', function (self, host)
									return not ModsUIIsPopupShown(host) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUIDialogEnd(host)
								end,
							}),
							}),
						PlaceObj('XTemplateMode', {
							'mode', "installed",
						}, {
							PlaceObj('XTemplateAction', {
								'ActionId', "open",
								'ActionName', T(7356, --[[XTemplate ModsUIDialog ActionName]] "Open"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "ButtonA",
								'ActionState', function (self, host)
									return ModsUIShowItemAction(host) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUISetDialogMode(host, "details", g_ParadoxModsContextObj:GetSelectedMod("installed_mods"))
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "enable",
								'ActionName', T(754117323318, --[[XTemplate ModsUIDialog ActionName]] "Enable"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "ButtonY",
								'ActionState', function (self, host)
									return ModsUIShowItemAction(host, "enabled", false) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUIToggleEnabled(nil, host, "installed_mods")
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "disable",
								'ActionName', T(251103844022, --[[XTemplate ModsUIDialog ActionName]] "Disable"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "ButtonY",
								'ActionState', function (self, host)
									return ModsUIShowItemAction(host, "enabled", true) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUIToggleEnabled(nil, host, "installed_mods")
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "uninstall",
								'ActionName', T(10122, --[[XTemplate ModsUIDialog ActionName]] "Uninstall"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "ButtonX",
								'ActionState', function (self, host)
									return ModsUIShowItemAction(host, "installed", true) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUIUninstallMod(nil, "installed_mods")
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "disableAll",
								'ActionName', T(123411309724, --[[XTemplate ModsUIDialog ActionName]] "Disable All"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "LeftThumbClick",
								'ActionState', function (self, host)
									return (ModsUIShowItemAction(host) and ModsUIGetEnableAllButtonState() == true) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUISetAllModsEnabledState(host, false)
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "enableAll",
								'ActionName', T(339914669630, --[[XTemplate ModsUIDialog ActionName]] "Enable All"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "LeftThumbClick",
								'ActionState', function (self, host)
									return (ModsUIShowItemAction(host) and ModsUIGetEnableAllButtonState() == false) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUISetAllModsEnabledState(host, true)
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "search",
								'ActionName', T(10123, --[[XTemplate ModsUIDialog ActionName]] "Search"),
								'ActionToolbar', "ActionBarRight",
								'ActionGamepad', "Back",
								'ActionState', function (self, host)
									return not ModsUIIsPopupShown(host) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUIConsoleSearch(host.idContentWrapper)
									host:UpdateActionViews(host)
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "filter",
								'ActionName', T(1000108, --[[XTemplate ModsUIDialog ActionName]] "Filter"),
								'ActionToolbar', "ActionBarRight",
								'ActionGamepad', "Start",
								'ActionState', function (self, host)
									return not ModsUIIsPopupShown(host) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUIChooseFilter(host.idContentWrapper)
									host:UpdateActionViews(host)
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "sort",
								'ActionName', T(10124, --[[XTemplate ModsUIDialog ActionName]] "Sort"),
								'ActionToolbar', "ActionBarRight",
								'ActionGamepad', "RightThumbClick",
								'ActionState', function (self, host)
									return not ModsUIIsPopupShown(host) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUIChooseSort(host.idContentWrapper)
									host:UpdateActionViews(host)
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "back",
								'ActionName', T(4165, --[[XTemplate ModsUIDialog ActionName]] "Back"),
								'ActionToolbar', "ActionBarRight",
								'ActionShortcut', "Escape",
								'ActionGamepad', "ButtonB",
								'ActionState', function (self, host)
									return not ModsUIIsPopupShown(host) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUIDialogEnd(host)
								end,
							}),
							}),
						PlaceObj('XTemplateMode', {
							'mode', "details",
						}, {
							PlaceObj('XTemplateAction', {
								'ActionId', "enable",
								'ActionName', T(754117323318, --[[XTemplate ModsUIDialog ActionName]] "Enable"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "ButtonY",
								'ActionState', function (self, host)
									return ModsUIShowItemAction(host, "enabled", false, host.idContent.context.ModID) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUIToggleEnabled(GetDialogModeParam(host), host)
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "disable",
								'ActionName', T(251103844022, --[[XTemplate ModsUIDialog ActionName]] "Disable"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "ButtonY",
								'ActionState', function (self, host)
									return ModsUIShowItemAction(host, "enabled", true, host.idContent.context.ModID) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUIToggleEnabled(GetDialogModeParam(host), host)
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "install",
								'ActionName', T(10121, --[[XTemplate ModsUIDialog ActionName]] "Install"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "ButtonX",
								'ActionState', function (self, host)
									local mod_id = host.idContent.context.ModID
									if g_PopsDownloadingMods[mod_id] then
										return "disabled"
									end
									return ModsUIShowItemAction(host, "installed", false, mod_id) or "hidden"
								end,
								'OnAction', function (self, host, source)
									if not g_ParadoxAccountLoggedIn then
										ModsUIOpenLoginPopup(host.idContentWrapper)
									else
										ModsUIInstallMod(GetDialogModeParam(host))
									end
									host:UpdateActionViews(host)
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "uninstall",
								'ActionName', T(10122, --[[XTemplate ModsUIDialog ActionName]] "Uninstall"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "ButtonX",
								'ActionState', function (self, host)
									return ModsUIShowItemAction(host, "installed", true, host.idContent.context.ModID) or "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUIUninstallMod(GetDialogModeParam(host))
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "rate",
								'ActionName', T(10383, --[[XTemplate ModsUIDialog ActionName]] "Rate Mod"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "LeftThumbClick",
								'ActionState', function (self, host)
									local context = GetDialogModeParam(host)
									return (context.Local or ModsUIIsPopupShown(host)) and "hidden"
								end,
								'OnAction', function (self, host, source)
									if not g_ParadoxAccountLoggedIn then
										ModsUIOpenLoginPopup(host.idContentWrapper)
									else
										ModsUIChooseModRating(host.idContentWrapper)
									end
									host:UpdateActionViews(host)
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "flag",
								'ActionName', T(12306, --[[XTemplate ModsUIDialog ActionName]] "Report"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "RightThumbClick",
								'ActionState', function (self, host)
									local context = GetDialogModeParam(host)
									return (context.Local or ModsUIIsPopupShown(host)) and "hidden"
								end,
								'OnAction', function (self, host, source)
									ModsUIChooseFlagReason(host.idContentWrapper)
									host:UpdateActionViews(host)
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "back",
								'ActionName', T(4165, --[[XTemplate ModsUIDialog ActionName]] "Back"),
								'ActionToolbar', "ActionBarRight",
								'ActionShortcut', "Escape",
								'ActionGamepad', "ButtonB",
								'ActionState', function (self, host)
									return not ModsUIIsPopupShown(host) or "hidden"
								end,
								'OnActionEffect', "back",
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "popupflagselect",
								'ActionName', T(835333740373, --[[XTemplate ModsUIDialog ActionName]] "Select"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "ButtonA",
								'ActionState', function (self, host)
									local popup = ModsUIIsPopupShown(host)
									return popup ~= "flag" and "hidden"
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "popupflagsubmit",
								'ActionName', T(10399, --[[XTemplate ModsUIDialog ActionName]] "Submit"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "Start",
								'ActionState', function (self, host)
									local popup = ModsUIIsPopupShown(host)
									if popup ~= "flag" then return "hidden" end
									return not host.mode_param.flag_reason and "disabled"
								end,
								'OnAction', function (self, host, source)
									ModsUIFlagMod(host)
									host:UpdateActionViews(host)
								end,
							}),
							PlaceObj('XTemplateAction', {
								'ActionId', "popuprateselect",
								'ActionName', T(835333740373, --[[XTemplate ModsUIDialog ActionName]] "Select"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "ButtonA",
								'ActionState', function (self, host)
									local popup = ModsUIIsPopupShown(host)
									return popup ~= "rate" and "hidden"
								end,
							}),
							}),
						PlaceObj('XTemplateMode', nil, {
							PlaceObj('XTemplateAction', {
								'ActionId', "select",
								'ActionName', T(131775917427, --[[XTemplate ModsUIDialog ActionName]] "Select"),
								'ActionToolbar', "ActionBarLeft",
								'ActionGamepad', "ButtonA",
								'ActionState', function (self, host)
									return not ModsUIIsPopupShown(host) or "hidden"
								end,
							}),
							}),
						PlaceObj('XTemplateAction', {
							'ActionId', "search",
							'ActionName', T(10123, --[[XTemplate ModsUIDialog ActionName]] "Search"),
							'ActionToolbar', "ActionBarLeft",
							'ActionShortcut', "Enter",
							'ActionGamepad', "ButtonY",
							'ActionState', function (self, host)
								local popup = ModsUIIsPopupShown(host)
								return popup ~= "search" and "hidden"
							end,
							'OnAction', function (self, host, source)
								local context = host.context
								if host.Mode == "browse" then
									if context.query ~= context.temp_query then
										context.query = context.temp_query
										context:GetMods()
									end
								else
									if context.installed_query ~= context.temp_query then
										context.installed_query = context.temp_query
										context:GetInstalledMods()
									end
								end
								ModsUIClosePopup(host)
							end,
						}),
						PlaceObj('XTemplateAction', {
							'ActionId', "popupcancel",
							'ActionName', T(3687, --[[XTemplate ModsUIDialog ActionName]] "Cancel"),
							'ActionToolbar', "ActionBarRight",
							'ActionShortcut', "Escape",
							'ActionGamepad', "ButtonB",
							'ActionState', function (self, host)
								local popup = ModsUIIsPopupShown(host)
								return (not popup or popup == "login") and "hidden"
							end,
							'OnAction', function (self, host, source)
								ModsUIClosePopup(host)
							end,
						}),
						PlaceObj('XTemplateAction', {
							'ActionId', "popupsortsave",
							'ActionName', T(12307, --[[XTemplate ModsUIDialog ActionName]] "Apply"),
							'ActionToolbar', "ActionBarLeft",
							'ActionGamepad', "ButtonA",
							'ActionState', function (self, host)
								local popup = ModsUIIsPopupShown(host)
								return popup ~= "sort" and "hidden"
							end,
							'OnAction', function (self, host, source)
								ModsUIClosePopup(host)
							end,
						}),
						PlaceObj('XTemplateAction', {
							'ActionId', "popupfiltersave",
							'ActionName', T(12307, --[[XTemplate ModsUIDialog ActionName]] "Apply"),
							'ActionToolbar', "ActionBarLeft",
							'ActionGamepad', "ButtonY",
							'ActionState', function (self, host)
								local popup = ModsUIIsPopupShown(host)
								return popup ~= "filter" and "hidden"
							end,
							'OnAction', function (self, host, source)
								if host.Mode == "installed" then
									ModsUISetInstalledTags()
									ModsUIClosePopup(host)
									host.context:GetInstalledMods()
								else
									ModsUISetTags()
									ModsUIClosePopup(host)
									host.context:GetMods()
								end
							end,
						}),
						PlaceObj('XTemplateAction', {
							'ActionId', "popupfilterclear",
							'ActionName', T(828218723298, --[[XTemplate ModsUIDialog ActionName]] "Clear Filters"),
							'ActionToolbar', "ActionBarLeft",
							'ActionGamepad', "ButtonX",
							'ActionState', function (self, host)
								local popup = ModsUIIsPopupShown(host)
								return popup ~= "filter" and "hidden"
							end,
							'OnAction', function (self, host, source)
								ModsUIClearFilter(GetDialog(host):GetMode())
							end,
						}),
						}),
					}),
				}),
			}),
		}),
})


/obj/item/stock_parts/circuitboard/resleever
	name = "circuitboard (cortical stack resleever)"
	build_path = /obj/machinery/resleever
	board_type = "machine"
	origin_tech = "{'biotech':3,'programming':3}"
	req_components = list(
							/obj/item/stack/cable_coil = 2,
							/obj/item/stock_parts/scanning_module = 1,
							/obj/item/stock_parts/manipulator = 3
	)
	additional_spawn_components = list(
							/obj/item/stock_parts/console_screen = 1,
							/obj/item/stock_parts/keyboard = 1,
							/obj/item/stock_parts/power/apc/buildable = 1,
	)

/obj/machinery/resleever
	name = "Cortical Stack Resleever"
	desc = "It's a machine that allows cortical stacks to be sleeved into new bodies."
	icon = 'icons/obj/Cryogenic2.dmi'
	icon_state = "body_scanner_0"
	anchored = 1
	density = 1
	idle_power_usage = 10
	active_power_usage = 4 KILOWATTS // A CT scan machine uses 1-15 kW depending on the model and equipment involved.

	base_type = /obj/machinery/resleever
	construct_state = /decl/machine_construction/default/panel_closed
	uncreated_component_parts = null
	stat_immune = 0

	var/mob/living/carbon/human/occupant = null
	var/obj/item/organ/internal/stack/lace = null

	var/remaining = 0
	var/timetosleeve = 120

/obj/machinery/resleever/Destroy()
	eject_occupant()
	eject_lace()
	return ..()

/obj/machinery/resleever/on_update_icon()
	icon_state = occupant ? "body_scanner_1" : "body_scanner_0"
	return ..()

/obj/machinery/resleever/components_are_accessible(var/path)
	return !remaining && ..()

/obj/machinery/resleever/cannot_transition_to(var/state_path, mob/user)
	if(remaining)
		return SPAN_NOTICE("You must wait for the process to finish!")
	return ..()

/obj/machinery/resleever/interface_interact(user)
	ui_interact(user)
	return TRUE

/obj/machinery/resleever/attackby(var/obj/item/O, var/mob/user)
	if((. = component_attackby(O, user)))
		return

	if(remaining)
		to_chat(user, SPAN_NOTICE("\The [src] is still running!"))
		return

	if(istype(O, /obj/item/organ/internal/stack))
		if(isnull(lace) && user.unEquip(O, src))
			to_chat(user, SPAN_NOTICE("You insert \the [O] into \the [src]."))
			lace = O
		else
			to_chat(user, SPAN_NOTICE("\The [src] already has \a [O] inside it!"))

	if(istype(O, /obj/item/grab))
		var/obj/item/grab/G = O
		if(try_enter(G.affecting, user))
			qdel(G)

/obj/machinery/resleever/receive_mouse_drop(mob/living/dropping, mob/living/user)
	try_enter(dropping, user)

/obj/machinery/resleever/proc/try_enter(var/mob/living/carbon/human/target, var/mob/user)
	if(!istype(target) || !istype(user))
		return FALSE

	if(user.incapacitated() || !user.Adjacent(src) || !user.Adjacent(target))
		return FALSE

	if(occupant)
		to_chat(user, SPAN_NOTICE("\The [src] already has an occupant!"))
		return FALSE

	if(target.client && target == user)
		if(alert(target, "Would you like to enter \the [src]?", "Enter?", "Yes", "No") == "Yes")
			occupant = target
			target.forceMove(src)
			target.client?.perspective = EYE_PERSPECTIVE
			target.client?.eye = src
			queue_icon_update()
			return TRUE
		return FALSE

	visible_message("[user] starts putting [target] into \the [src].", range = 3)

	if(do_after(user, 2 SECONDS, src) && !QDELETED(target))
		if(!occupant)
			occupant = target
			target.forceMove(src)
			target.client?.perspective = EYE_PERSPECTIVE
			target.client?.eye = src
			queue_icon_update()
			return TRUE
		else
			to_chat(user, SPAN_NOTICE("\The [src] already has an occupant!"))
	return FALSE

/obj/machinery/resleever/Process()
	if(!operable())
		remaining = 0
		update_use_power(POWER_USE_OFF)
		return

	if(remaining > 1)
		// Actively running
		update_use_power(POWER_USE_ACTIVE)
		SET_STATUS_MAX(occupant, STAT_PARA, 4)
		remaining -= 1

		// If we are 66% done, give the occupant some notice.
		if(remaining == timetosleeve / 3)
			to_chat(occupant, SPAN_NOTICE("You feel a wash of sensation as your senses begin to flood your mind. You will come to soon."))

		return

	if( remaining == 1)
		remaining = 0
		update_use_power(POWER_USE_IDLE)
		playsound(loc, 'sound/machines/ping.ogg', 100, vary = TRUE)
		visible_message("\The [src] pings as it completes its procedure!", "You hear a ping.", range = 3)

/obj/machinery/resleever/ui_interact(mob/user, ui_key = "main", var/datum/nanoui/ui = null, var/force_open = 1)
	user.set_machine(src)
	var/list/data = list(
		"name" = occupant?.name,
		"lace" = lace?.name,
		"isOccupiedEjectable" = occupant && !remaining,
		"isLaceEjectable" = lace && !remaining,
		"active" = !!remaining,
		"remaining" = remaining ? timetosleeve - remaining : 0,	// Inverted for NanoUI
		"timetosleeve" = timetosleeve,
		"ready" = occupant && lace && !remaining
	)

	ui = SSnano.try_update_ui(user, src, ui_key, ui, data, force_open)
	if (!ui)
		ui = new(user, src, ui_key, "resleever.tmpl", "Cortical Stack Resleever", 400, 350)
		ui.set_initial_data(data)
		ui.open()
		ui.set_auto_update(1)


/obj/machinery/resleever/OnTopic(var/mob/user, var/list/href_list)
	switch(href_list["action"])
		if("begin")
			if(!occupant)
				to_chat(user, "No occupant in \the [src]!")
				return TOPIC_REFRESH
			if(occupant.get_organ(BP_STACK))
				to_chat(user, "Occupant already has a mind.")
				return TOPIC_REFRESH
			if(sleeve())
				remaining = timetosleeve
			return TOPIC_REFRESH
		if("eject")
			eject_occupant()
			return TOPIC_REFRESH
		if("ejectlace")
			eject_lace()
			return TOPIC_REFRESH

/obj/machinery/resleever/state_transition(var/decl/machine_construction/new_state)
	. = ..()
	if(istype(new_state))
		updateUsrDialog()
		eject_occupant()

/obj/machinery/resleever/proc/sleeve()
	if(lace && occupant)
		var/obj/item/organ/O = occupant.get_organ(lace.parent_organ)
		if(istype(O))
			occupant.add_organ(lace, O)
			lace = null
			playsound(loc, 'sound/machines/twobeep.ogg', 50, vary = TRUE)
			visible_message("\The [src] beeps softly as it begins its procedure.", "You hear a beep.", range = 3)
			return TRUE
	return FALSE // Return false if the the lace doesn't exist, the lace is busy prompting, no occupant, or the occupant's head (parrent organ) doesn't exist.

/obj/machinery/resleever/proc/eject_occupant()
	if(!occupant)
		return
	occupant.forceMove(loc)
	occupant.reset_view(null)
	occupant = null
	queue_icon_update()

/obj/machinery/resleever/proc/eject_lace()
	if(!(lace))
		return
	lace.forceMove(loc)
	lace = null

/obj/machinery/resleever/relaymove()
	..()
	eject_occupant()

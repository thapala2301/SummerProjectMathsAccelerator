/* ============================================================================
   Reusable slider row
   ============================================================================ */

// This component renders one labelled slider
// The parent panel passes in the text, value, limits and change handler
// The { ... } in the function argument is object destructuring
// It pulls named props out of one props object into local variables
export default function ControlSlider({
    label,
    value,
    min,
    max,
    step,
    onChange,
}) {
    return (
        <label className="block rounded-xl bg-white/7 p-3 ring-1 ring-white/10">
            {/* Show the slider name on the left and the current number on the right */}
            <div className="mb-2 flex items-center justify-between gap-3 text-xs">
                <span className="font-medium text-slate-200">{label}</span>
                {/* Show more decimal places for fractional sliders than whole-number sliders */}
                {/* step < 1 ? 3 : 0 is a ternary expression: if step is less than 1 use 3, otherwise use 0 */}
                <span className="tabular-nums text-slate-400">{value.toFixed(step < 1 ? 3 : 0)}</span>
            </div>
            {/* Render the actual HTML range input that the user drags left and right */}
            <input
                className="w-full accent-slate-200"
                type="range"
                min={min}
                max={max}
                step={step}
                value={value}
                // Convert the browser's text value into a Number before passing it upward
                // event.target.value comes from the DOM as text even for a range input
                onChange={(event) => onChange(Number(event.target.value))}
            />
        </label>
    );
}
